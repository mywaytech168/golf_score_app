package com.aethertek.orvia

import android.graphics.SurfaceTexture
import android.opengl.*
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * EGL + OpenGL ES 2.0 pipeline：
 *   decoder (SurfaceTexture / OES) → rotate+scale shader → encoder input Surface
 *
 * 用於來源解析度與目標解析度不符時，在 trim 過程中正確做旋轉與縮放，
 * 避免直接 Surface-to-Surface 時部分硬體 encoder 輸出錯誤尺寸的問題。
 */
class EglSurfaceProcessor(private val encoderInputSurface: Surface) {

    companion object {
        private const val TAG = "EglSurfaceProcessor"

        private const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec2 aTexCoord;
            varying vec2 vTexCoord;
            uniform mat4 uMVP;
            uniform mat4 uTexMatrix;
            void main() {
                gl_Position = uMVP * aPosition;
                vTexCoord = (uTexMatrix * vec4(aTexCoord, 0.0, 1.0)).xy;
            }
        """

        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, vTexCoord);
            }
        """

        // 全螢幕四邊形
        private val QUAD_VERTS = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)
        private val QUAD_TEX   = floatArrayOf( 0f,  0f, 1f,  0f,  0f, 1f, 1f, 1f)
    }

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext  = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface  = EGL14.EGL_NO_SURFACE
    private var program = 0
    private var texId   = 0

    private lateinit var surfaceTexture: SurfaceTexture
    val decoderSurface: Surface get() = _decoderSurface
    private lateinit var _decoderSurface: Surface

    private val frameAvailable = AtomicBoolean(false)
    private val texMatrix = FloatArray(16)

    // ── 初始化 EGL + SurfaceTexture ────────────────────────────────────────

    fun setup(srcWidth: Int, srcHeight: Int) {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(eglDisplay != EGL14.EGL_NO_DISPLAY) { "eglGetDisplay failed" }
        EGL14.eglInitialize(eglDisplay, null, 0, null, 0)

        val cfgAttribs = intArrayOf(
            EGL14.EGL_RED_SIZE,   8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE,  8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGLExt.EGL_RECORDABLE_ANDROID, 1,   // MediaCodec 需要
            EGL14.EGL_NONE
        )
        val configs    = arrayOfNulls<EGLConfig>(1)
        val numCfg     = IntArray(1)
        EGL14.eglChooseConfig(eglDisplay, cfgAttribs, 0, configs, 0, 1, numCfg, 0)
        check(numCfg[0] > 0) { "eglChooseConfig: no suitable config" }

        val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        eglContext = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)
        check(eglContext != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }

        val winAttribs = intArrayOf(EGL14.EGL_NONE)
        eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], encoderInputSurface, winAttribs, 0)
        check(eglSurface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface failed" }

        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

        // OES Texture（decoder 輸出目標）
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        texId = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S,     GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T,     GLES20.GL_CLAMP_TO_EDGE)

        surfaceTexture = SurfaceTexture(texId)
        surfaceTexture.setDefaultBufferSize(srcWidth, srcHeight)
        surfaceTexture.setOnFrameAvailableListener { frameAvailable.set(true) }
        _decoderSurface = Surface(surfaceTexture)

        program = buildProgram(VERTEX_SHADER.trimIndent(), FRAGMENT_SHADER.trimIndent())
        Log.d(TAG, "setup OK: src=${srcWidth}×${srcHeight}")
    }

    // ── 等待 decoder 幀就緒，然後渲染到 encoder surface ─────────────────────

    /**
     * @param rotationDeg 來源影片的 rotation metadata（0/90/180/270）
     * @param dstWidth / dstHeight encoder 輸出尺寸（portrait 順序）
     * @param ptsUs 輸出 PTS（microseconds，從 0 開始）
     */
    fun awaitAndRender(rotationDeg: Int, dstWidth: Int, dstHeight: Int, ptsUs: Long,
                       flipHorizontal: Boolean = false) {
        // 最多等 200ms
        val deadline = System.currentTimeMillis() + 200L
        while (!frameAvailable.getAndSet(false)) {
            if (System.currentTimeMillis() > deadline) {
                Log.w(TAG, "awaitFrame timeout ptsUs=$ptsUs")
                return
            }
            Thread.sleep(1)
        }
        surfaceTexture.updateTexImage()
        surfaceTexture.getTransformMatrix(texMatrix)

        GLES20.glViewport(0, 0, dstWidth, dstHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glUseProgram(program)

        // MVP：旋轉 + 水平翻轉（前鏡頭）
        // ★ 負號（-rotationDeg），前提：呼叫端已把 KEY_ROTATION 從 decoder format 剝除
        //   （VideoTrimmer 會剝除；否則 decoder 在 Surface 模式會自行套用旋轉 → 雙重旋轉）。
        //   實測校正史（rotation=90 來源）：
        //     未剝除 + rotateM(-90) → 輸出歪 -90（decoder 已轉正，MVP 又轉）
        //     未剝除 + rotateM(+90) → 輸出歪 +90（同上，反向）
        //     已剝除 + rotateM(+90) → 輸出倒立 180
        //     已剝除 + rotateM(-90) → 正確 ✓
        //   rotation=0（純縮放）不受符號影響。
        val mvp = FloatArray(16)
        Matrix.setIdentityM(mvp, 0)
        Matrix.rotateM(mvp, 0, -rotationDeg.toFloat(), 0f, 0f, 1f)
        if (flipHorizontal) {
            // X 軸 scale = -1 → 水平翻轉
            Matrix.scaleM(mvp, 0, -1f, 1f, 1f)
        }

        // Vertex buffer
        val vBuf = ByteBuffer.allocateDirect(QUAD_VERTS.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer().also { it.put(QUAD_VERTS); it.flip() }
        val tBuf = ByteBuffer.allocateDirect(QUAD_TEX.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer().also { it.put(QUAD_TEX); it.flip() }

        val posLoc    = GLES20.glGetAttribLocation(program,  "aPosition")
        val texLoc    = GLES20.glGetAttribLocation(program,  "aTexCoord")
        val mvpLoc    = GLES20.glGetUniformLocation(program, "uMVP")
        val texMatLoc = GLES20.glGetUniformLocation(program, "uTexMatrix")
        val sampLoc   = GLES20.glGetUniformLocation(program, "sTexture")

        GLES20.glEnableVertexAttribArray(posLoc)
        GLES20.glVertexAttribPointer(posLoc, 2, GLES20.GL_FLOAT, false, 0, vBuf)
        GLES20.glEnableVertexAttribArray(texLoc)
        GLES20.glVertexAttribPointer(texLoc, 2, GLES20.GL_FLOAT, false, 0, tBuf)

        GLES20.glUniformMatrix4fv(mvpLoc,    1, false, mvp,      0)
        GLES20.glUniformMatrix4fv(texMatLoc, 1, false, texMatrix, 0)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texId)
        GLES20.glUniform1i(sampLoc, 0)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        // 設定 PTS 並送出（ns）
        EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, ptsUs * 1_000L)
        EGL14.eglSwapBuffers(eglDisplay, eglSurface)
    }

    // ── 釋放 ──────────────────────────────────────────────────────────────

    fun release() {
        runCatching { _decoderSurface.release() }
        runCatching { surfaceTexture.release() }
        if (program != 0) { GLES20.glDeleteProgram(program); program = 0 }
        if (texId != 0)   { GLES20.glDeleteTextures(1, intArrayOf(texId), 0); texId = 0 }
        EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(eglDisplay, eglSurface)
        if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(eglDisplay, eglContext)
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) EGL14.eglTerminate(eglDisplay)
        Log.d(TAG, "released")
    }

    // ── GL helpers ─────────────────────────────────────────────────────────

    private fun compileShader(type: Int, src: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, src)
        GLES20.glCompileShader(shader)
        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw RuntimeException("Shader compile error: $log")
        }
        return shader
    }

    private fun buildProgram(vertSrc: String, fragSrc: String): Int {
        val vert = compileShader(GLES20.GL_VERTEX_SHADER,   vertSrc)
        val frag = compileShader(GLES20.GL_FRAGMENT_SHADER, fragSrc)
        val prog = GLES20.glCreateProgram()
        GLES20.glAttachShader(prog, vert)
        GLES20.glAttachShader(prog, frag)
        GLES20.glLinkProgram(prog)
        val status = IntArray(1)
        GLES20.glGetProgramiv(prog, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(prog)
            GLES20.glDeleteProgram(prog)
            throw RuntimeException("Program link error: $log")
        }
        GLES20.glDeleteShader(vert)
        GLES20.glDeleteShader(frag)
        return prog
    }
}
