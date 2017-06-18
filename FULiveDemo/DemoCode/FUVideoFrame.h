//
//  FUVideoFrame.h
//  FUVideoCamera
//
//  Created by 千山暮雪 on 2017/6/16.
//  Copyright © 2017年 千山暮雪. All rights reserved.
//

struct FUVideoFrame {
    void *bgraImg;
    size_t width;
    size_t height;
    size_t size ;
    size_t stride;
    BOOL isUsed ; //判断是否使用过
};
