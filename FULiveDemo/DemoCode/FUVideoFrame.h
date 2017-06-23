//
//  FUVideoFrame.h
//  FUVideoCamera
//
//  Created by 千山暮雪 on 2017/6/16.
//  Copyright © 2017年 千山暮雪. All rights reserved.
//

typedef enum : NSUInteger {
    FUVideoFrameTypeBGRA,
    FUVideoFrameTypeYUV,
} FUVideoFrameType;

struct FUVideoFrame {
    
    BOOL isUsed ; //判断是否使用过
    FUVideoFrameType frameType ;
    int width;
    int height;
    
    // BGRA
    void *bgraImg;
    int size ;
    int stride ;
    // YUV
    void *p_Y ;
    void *p_CbCr ;
    int stride_Y ;
    int stride_CbCr ;
};
