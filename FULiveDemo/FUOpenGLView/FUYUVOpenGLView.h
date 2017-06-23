//
//  FUYUVOpenGLView.h
//  FULiveDemo
//
//  Created by 千山暮雪 on 2017/6/19.
//  Copyright © 2017年 刘洋. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FUYUVOpenGLView : UIView

@property (nonatomic , assign) BOOL isFullYUVRange;

- (void)setupGL;
- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;

// 拍照并保存
- (void)takePhotoAndSave;
@end
