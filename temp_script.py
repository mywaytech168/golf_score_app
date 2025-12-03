from PIL import Image, ImageDraw
import os
w,h=900,900
img=Image.new('RGBA',(w,h),(0,0,0,0))
d=ImageDraw.Draw(img)
stroke=(255,255,255,220)
center=(w//2, int(h*0.65))
base_width=280
body_h=190
leg_h=170
head_r=26
ball_r=55
arrow_len=60

for dir_sign in (-1,1):
    hip=(center[0]+dir_sign*base_width//2, center[1]-int(body_h*0.15))
    shoulder=(hip[0]+dir_sign*int(base_width*0.08), hip[1]-int(body_h*0.6))
    head=(shoulder[0]+dir_sign*int(base_width*0.05), shoulder[1]-int(head_r*1.6))
    hand=(center[0]+dir_sign*int(base_width*0.3), center[1]+int(body_h*0.12))
    foot_front=(center[0]+dir_sign*int(base_width*0.55), center[1]+leg_h)
    foot_back=(center[0]+dir_sign*int(base_width*0.35), center[1]+int(leg_h*0.9))
    elbow=(shoulder[0]+dir_sign*int(base_width*0.06), shoulder[1]+int(body_h*0.18))
    club_end=(center[0]+dir_sign*int(base_width*0.08), center[1]+int(ball_r*0.2))

    d.line([hip, foot_front], fill=stroke, width=5, joint='curve')
    d.line([hip, foot_back], fill=stroke, width=5, joint='curve')
    d.line([hip, shoulder], fill=stroke, width=5, joint='curve')
    d.line([shoulder, head], fill=stroke, width=5, joint='curve')
    d.ellipse([head[0]-head_r, head[1]-head_r, head[0]+head_r, head[1]+head_r], outline=stroke, width=5)
    d.line([shoulder, elbow, hand], fill=stroke, width=5, joint='curve')
    d.line([hand, club_end], fill=stroke, width=5, joint='curve')

ball_center=(center[0], center[1]+int(ball_r*0.4))
d.ellipse([ball_center[0]-ball_r, ball_center[1]-ball_r, ball_center[0]+ball_r, ball_center[1]+ball_r], outline=stroke, width=5)
arrow_top=(ball_center[0], ball_center[1]-arrow_len//2)
arrow_bottom=(ball_center[0], ball_center[1]+arrow_len//2)
arrow_left=(narrow_top[0]-15, narrow_top[1]+20)
narrow_right=(narrow_top[0]+15, narrow_top[1]+20)
d.line([narrow_bottom, narrow_top], fill=stroke, width=5)
d.line([narrow_top, narrow_left], fill=stroke, width=5)
d.line([narrow_top, narrow_right], fill=stroke, width=5)

os.makedirs('assets/overlays', exist_ok=True)
img.save('assets/overlays/stance_overlay.png')
print('saved at', 'assets/overlays/stance_overlay.png', 'size', img.size)
