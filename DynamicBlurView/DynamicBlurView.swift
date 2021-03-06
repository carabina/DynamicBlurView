//
//  DynamicBlurView.swift
//  DynamicBlurView
//
//  Created by Kyohei Ito on 2015/04/08.
//  Copyright (c) 2015年 kyohei_ito. All rights reserved.
//

import UIKit
import Accelerate

public class DynamicBlurView: UIView {
    private class BlurLayer: CALayer {
        @NSManaged var blurRadius: CGFloat
        
        override class func needsDisplayForKey(key: String) -> Bool {
            if key == "blurRadius" {
                return true
            }
            return super.needsDisplayForKey(key)
        }
    }
    
    public enum DynamicMode {
        case Tracking   // only scrolling
        case Common     // full refreshing
        
        func mode() -> String {
            switch self {
            case .Tracking:
                return UITrackingRunLoopMode
            case .Common:
                return NSRunLoopCommonModes
            }
        }
    }
    
    private var fromBlurRadius: CGFloat?
    private var displayLink: CADisplayLink?
    private let DisplayLinkSelector: Selector = "displayDidRefresh:"
    private var blurLayer: BlurLayer {
        return layer as! BlurLayer
    }
    
    private var blurPresentationLayer: BlurLayer {
        if let layer = blurLayer.presentationLayer() as? BlurLayer {
            return layer
        }
        
        return blurLayer
    }
    
    public var blurRadius: CGFloat {
        set { blurLayer.blurRadius = newValue }
        get { return blurLayer.blurRadius }
    }
    
    /// Default is Tracking.
    public var dynamicMode: DynamicMode = .Tracking {
        didSet {
            if dynamicMode != oldValue {
                linkForDisplay()
            }
        }
    }
    
    /// Default is 3.
    public var iterations: Int = 3
    
    public override class func layerClass() -> AnyClass {
        return BlurLayer.self
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        userInteractionEnabled = false
    }
    
    public required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        userInteractionEnabled = false
    }
    
    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        if superview == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else {
            linkForDisplay()
        }
    }
    
    public override func actionForLayer(layer: CALayer!, forKey event: String!) -> CAAction! {
        if event == "blurRadius" {
            fromBlurRadius = nil
            
            if let action = super.actionForLayer(layer, forKey: "backgroundColor") as? CAAnimation {
                fromBlurRadius = blurPresentationLayer.blurRadius
                
                let animation = CABasicAnimation()
                animation.fromValue = fromBlurRadius
                animation.beginTime = action.beginTime
                animation.duration = action.duration
                animation.speed = action.speed
                animation.timeOffset = action.timeOffset
                animation.repeatCount = action.repeatCount
                animation.repeatDuration = action.repeatDuration
                animation.autoreverses = action.autoreverses
                animation.fillMode = action.fillMode
                
                //CAAnimation attributes
                animation.timingFunction = action.timingFunction
                animation.delegate = action.delegate
                
                return animation
            }
        }
        
        return super.actionForLayer(layer, forKey: event)
    }
    
    public override func displayLayer(layer: CALayer!) {
        var blurRadius = blurPresentationLayer.blurRadius
        
        if let radius = fromBlurRadius {
            if layer.presentationLayer() == nil {
                blurRadius = radius
            }
        } else {
            blurRadius = blurLayer.blurRadius
        }
        
        let blurredImag = capturedImage().blurredImage(blurRadius, iterations: iterations)
        
        setContentImage(blurredImag)
    }
    
    private func linkForDisplay() {
        displayLink?.invalidate()
        displayLink = UIScreen.mainScreen().displayLinkWithTarget(self, selector: DisplayLinkSelector)
        displayLink?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: dynamicMode.mode())
    }
    
    private func setContentImage(image: UIImage) {
        layer.contents = image.CGImage
        layer.contentsScale = image.scale
    }
    
    private func prepareLayer() -> [CALayer]? {
        let sublayers = superview?.layer.sublayers as? [CALayer]
        
        return sublayers?.reduce([], combine: { acc, layer -> [CALayer] in
            if acc.isEmpty {
                if layer != self.blurLayer {
                    return acc
                }
            }
            
            if layer.hidden == false {
                layer.hidden = true
                
                return acc + [layer]
            }
            
            return acc
        })
    }
    
    private func restoreLayer(layers: [CALayer]) {
        layers.map { $0.hidden = false }
    }
    
    private func capturedImage() -> UIImage {
        let bounds = blurLayer.convertRect(blurLayer.bounds, toLayer: superview?.layer)
        
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, 0)
        let context = UIGraphicsGetCurrentContext()
        CGContextTranslateCTM(context, -bounds.origin.x, -bounds.origin.y)
        
        let layers = prepareLayer()
        superview?.layer.renderInContext(context)
        if let layers = layers {
            restoreLayer(layers)
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    func displayDidRefresh(displayLink: CADisplayLink) {
        displayLayer(blurLayer)
    }
}

private extension UIImage {
    func blurredImage(radius: CGFloat, iterations: Int) -> UIImage! {
        if floorf(Float(size.width)) * floorf(Float(size.height)) <= 0.0 {
            return self
        }
        
        let imageRef = CGImage
        var boxSize = UInt32(radius * scale)
        if boxSize % 2 == 0 {
            boxSize++
        }
        
        let height = CGImageGetHeight(imageRef)
        let width = CGImageGetWidth(imageRef)
        let rowBytes = CGImageGetBytesPerRow(imageRef)
        let bytes = rowBytes * height
        
        let inData = malloc(bytes)
        var inBuffer = vImage_Buffer(data: inData, height: UInt(height), width: UInt(width), rowBytes: rowBytes)
        
        let outData = malloc(bytes)
        var outBuffer = vImage_Buffer(data: outData, height: UInt(height), width: UInt(width), rowBytes: rowBytes)
        
        let tempFlags = vImage_Flags(kvImageEdgeExtend + kvImageGetTempBufferSize)
        let tempSize = vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, nil, 0, 0, boxSize, boxSize, nil, tempFlags)
        let tempBuffer = malloc(tempSize)
        
        let provider = CGImageGetDataProvider(imageRef)
        let copy = CGDataProviderCopyData(provider)
        let source = CFDataGetBytePtr(copy)
        memcpy(inBuffer.data, source, bytes)
        
        let flags = vImage_Flags(kvImageEdgeExtend)
        for index in 0 ..< iterations {
            vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, tempBuffer, 0, 0, boxSize, boxSize, nil, flags)
            
            let temp = inBuffer.data
            inBuffer.data = outBuffer.data
            outBuffer.data = temp
        }
        
        free(outBuffer.data)
        free(tempBuffer)
        
        let space = CGImageGetColorSpace(imageRef)
        let bitmapInfo = CGImageGetBitmapInfo(imageRef)
        let ctx = CGBitmapContextCreate(inBuffer.data, Int(inBuffer.width), Int(inBuffer.height), 8, inBuffer.rowBytes, space, bitmapInfo)
        
        let bitmap = CGBitmapContextCreateImage(ctx);
        let image = UIImage(CGImage: bitmap, scale: scale, orientation: imageOrientation)
        free(inBuffer.data)
        
        return image
    }
}
