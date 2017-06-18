//
//  OpenGLBGRAView.h
//  BGRA
//
//  Created by 千山暮雪 on 2017/5/10.
//  Copyright © 2017年 千山暮雪. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface FUOpenGLView : UIView

- (void)setupGL;

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer IsMirror:(BOOL)isMirror ;

// 拍照并保存
- (void)takePhotoAndSave;

@end
