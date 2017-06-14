/*
 
 The MIT License (MIT)
 Copyright (c) 2017 Dalton Hinterscher
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
 ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
 THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 */

import UIKit

#if CARTHAGE_CONFIG
    import MarqueeLabelSwift
#else
    import MarqueeLabel
#endif

public class BaseNotificationBanner: UIView {
    
    /// The height of the banner when it is presented
    public var bannerHeight: CGFloat = 64.0
    
    /// The topmost label of the notification if a custom view is not desired
    public internal(set) var titleLabel: MarqueeLabel?
    
    /// The time before the notificaiton is automatically dismissed
    public var duration: TimeInterval = 5.0 {
        didSet {
            updateMarqueeLabelsDurations()
        }
    }
    
    /// If false, the banner will not be dismissed until the developer programatically dismisses it
    public var autoDismiss: Bool = true {
        didSet {
            if !autoDismiss {
                dismissOnTap = false
                dismissOnSwipeUp = false
            }
        }
    }

    public var overlapStatusBar: Bool = false
    
    /// The type of haptic to generate when a banner is displayed
    public var haptic: BannerHaptic = .heavy
    
    /// If true, notification will dismissed when tapped
    public var dismissOnTap: Bool = true
    
    /// If true, notification will dismissed when swiped up
    public var dismissOnSwipeUp: Bool = true
    
    /// Closure that will be executed if the notification banner is tapped
    public var onTap: (() -> Void)?

    /// Closure that will be executed if the notification banner is swiped up
    public var onSwipeUp: (() -> Void)?

    /// Closure that will be executed if the notification banner is going to appear
    public var willAppear: (() -> Void)?

    /// Closure that will be executed if the notification banner is going to disappear
    public var willDisappear: (() -> Void)?

    /// Wether or not the notification banner is currently being displayed
    public private(set) var isDisplaying: Bool = false

    /// The view that the notification layout is presented on. The constraints/frame of this should not be changed
    internal var contentView: UIView!
    
    /// The default padding between edges and views
    internal var padding: CGFloat = 15.0
    
    /// Used by the banner queue to determine wether a notification banner was placed in front of it in the queue
    var isSuspended: Bool = false
    
    /// Responsible for positioning and auto managing notification banners
    private let bannerQueue: NotificationBannerQueue = NotificationBannerQueue.default
    
    /// The main window of the application which banner views are placed on
    private let appWindow: UIWindow = UIApplication.shared.delegate!.window!!

    /// The view controller to display the banner on. This is useful if you are wanting to display a banner underneath a navigation bar
    private weak var parentViewController: UIViewController?
    
    public override var backgroundColor: UIColor? {
        get {
            return contentView.backgroundColor
        } set {
            contentView.backgroundColor = newValue
        }
    }
    
    init(style: BannerStyle, colors: BannerColorsProtocol? = nil) {
        super.init(frame: .zero)
        
        contentView = UIView()
        addSubview(contentView)
        
        contentView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        
        if let colors = colors {
            backgroundColor = colors.color(for: style)
        } else {
            backgroundColor = BannerColors().color(for: style)
        }
        
        let swipeUpGesture = UISwipeGestureRecognizer(target: self, action: #selector(onSwipeUpGestureRecognizer))
        swipeUpGesture.direction = .up
        addGestureRecognizer(swipeUpGesture)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onOrientationChanged),
                                               name: NSNotification.Name.UIDeviceOrientationDidChange,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(statusBarFrameWillChange(notification:)),
                                               name: NSNotification.Name.UIApplicationWillChangeStatusBarFrame,
                                               object: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /**
        Dismisses the NotificationBanner and shows the next one if there is one to show on the queue
    */
    public func dismiss(completion: (() -> Void)? = nil) {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(dismiss),
                                               object: nil)
        let duration = UIView.inheritedAnimationDuration > 0 ? UIView.inheritedAnimationDuration : 0.5

        UIView.animate(withDuration: duration, animations: {
            self.frame.origin.y = -self.bannerHeight + UIApplication.shared.statusBarFrame.height

            let rootView = self.appWindow.rootViewController!.view!
            rootView.frame.size.height = UIScreen.main.bounds.height
            rootView.frame.origin.y = 0
            rootView.setNeedsLayout()
            rootView.layoutIfNeeded()

            self.willDisappear?()
            self.willDisappear = nil
        }) { (completed) in
            self.removeFromSuperview()
            self.isDisplaying = false
            self.bannerQueue.showNext()
            completion?()

            self.onTap = nil
            self.onSwipeUp = nil
        }
    }
    
    /**
        Places a NotificationBanner on the queue and shows it if its the first one in the queue
        - parameter queuePosition: The position to show the notification banner. If the position is .front, the
        banner will be displayed immediately
    */
    public func show(queuePosition: QueuePosition = .back, on viewController: UIViewController? = nil) {
        parentViewController = viewController
        show(placeOnQueue: true, queuePosition: queuePosition)
    }
    
    /**
        Places a NotificationBanner on the queue and shows it if its the first one in the queue
        - parameter placeOnQueue: If false, banner will not be placed on the queue and will be showed/resumed immediately
        - parameter queuePosition: The position to show the notification banner. If the position is .front, the
        banner will be displayed immediately
    */
    func show(placeOnQueue: Bool, queuePosition: QueuePosition = .back) {
        
        if placeOnQueue {
            bannerQueue.addBanner(self, queuePosition: queuePosition)
        } else {
            self.frame = CGRect(x: 0,
                                y: -self.bannerHeight + UIApplication.shared.statusBarFrame.height,
                                width: appWindow.frame.width,
                                height: self.bannerHeight)
            self.setNeedsLayout()
            self.layoutIfNeeded()
            
            if let parentViewController = parentViewController {
                parentViewController.view.addSubview(self)
                if statusBarShouldBeShown() {
                    appWindow.windowLevel = UIWindowLevelNormal
                }
            } else {
                appWindow.addSubview(self)

                if overlapStatusBar {
                    appWindow.windowLevel = UIWindowLevelStatusBar + 1
                }
            }

            let duration = UIView.inheritedAnimationDuration > 0 ? UIView.inheritedAnimationDuration : 0.5

            UIView.animate(withDuration: duration, animations: {
                BannerHapticGenerator.generate(self.haptic)

                self.frame.origin.y = UIApplication.shared.statusBarFrame.height

                let verticalOffset = self.bannerHeight + UIApplication.shared.statusBarFrame.height
                let rootView = self.appWindow.rootViewController!.view!
                rootView.frame.size.height = UIScreen.main.bounds.height - verticalOffset
                rootView.frame.origin.y = verticalOffset
                rootView.setNeedsLayout()
                rootView.layoutIfNeeded()

                self.willAppear?()
                self.willAppear = nil
            }) { (completed) in
                
                self.isDisplaying = true
                let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.onTapGestureRecognizer))
                self.addGestureRecognizer(tapGestureRecognizer)
                
                /* We don't want to add the selector if another banner was queued in front of it
                   before it finished animating or if it is meant to be shown infinitely
                */
                if !self.isSuspended && self.autoDismiss {
                    self.perform(#selector(self.dismiss), with: nil, afterDelay: self.duration)
                }
            }
        }
    }
    
    /**
        Suspends a notification banner so it will not be dismissed. This happens because a new notification banner was placed in front of it on the queue.
    */
    func suspend() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(dismiss), object: nil)
        isSuspended = true
        isDisplaying = false
    }
    
    /**
        Resumes a notification banner immediately.
    */
    func resume() {
        if autoDismiss {
            self.perform(#selector(dismiss), with: nil, afterDelay: self.duration)
            isSuspended = false
            isDisplaying = true
        }
    }
    
    /**
        Changes the frame of the notificaiton banner when the orientation of the device changes
    */
    private dynamic func onOrientationChanged() {
        self.frame = CGRect(x: self.frame.origin.x, y: self.frame.origin.y, width: appWindow.frame.width, height: self.frame.height)
    }

    private dynamic func statusBarFrameWillChange(notification: Notification) {
        if isDisplaying {
            let duration = UIView.inheritedAnimationDuration > 0 ? UIView.inheritedAnimationDuration : 0.31

            DispatchQueue.main.async {
                UIView.animate(withDuration: duration, animations: {
                    self.frame.origin.y = UIApplication.shared.statusBarFrame.height

                    let verticalOffset = self.bannerHeight + UIApplication.shared.statusBarFrame.height
                    let rootView = self.appWindow.rootViewController!.view!
                    rootView.frame.size.height = UIScreen.main.bounds.height - verticalOffset
                    rootView.frame.origin.y = verticalOffset
                    rootView.setNeedsLayout()
                    rootView.layoutIfNeeded()
                })
            }
        }
    }
    
    /**
        Called when a notification banner is tapped
    */
    private dynamic func onTapGestureRecognizer() {
        if dismissOnTap {
            dismiss()
        }
        
        onTap?()
    }
    
    /**
        Called when a notification banner is swiped up
    */
    private dynamic func onSwipeUpGestureRecognizer() {
        if dismissOnSwipeUp {
            dismiss()
        }
        
        onSwipeUp?()
    }
    
    /**
        Determines wether or not the status bar should be shown when displaying a banner underneath
        the navigation bar
     */
    private func statusBarShouldBeShown() -> Bool {
        guard overlapStatusBar else {
            return true
        }

        for banner in bannerQueue.banners {
            if banner.parentViewController == nil {
                return false
            }
        }
        
        return true
    }

    /**
        Updates the scrolling marquee label duration
    */
    internal func updateMarqueeLabelsDurations() {
        titleLabel?.speed = .duration(CGFloat(duration - 3))
    }
    
}

