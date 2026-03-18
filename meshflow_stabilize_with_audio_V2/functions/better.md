2️⃣ OpenCV 可转移到 GPU 的操作
OpenCV 操作	当前用途	GPU 加速库	优化潜力
cv2.cvtColor() (BGR→GRAY)	第 406 行	CUDA (cv2.cuda.cvtColor)	2-5 倍
cv2.calcOpticalFlowPyrLK()	第 415-420 行	CUDA (cv2.cuda.PyrLKOpticalFlow)	3-10 倍
cv2.FastFeatureDetector.detect()	第 410-412 行	CUDA (自定义 kernel 或 OpenCV CUDA)	2-5 倍
cv2.findHomography() (RANSAC)	第 355, 360 行	GPU 支持有限 需自定义	1-2 倍
cv2.remap() (warping)	第 664-668 行	CUDA (cv2.cuda.remap)	3-8 倍
cv2.medianBlur()	第 299-300 行	CUDA (cv2.cuda.medianBlur)	2-4 倍