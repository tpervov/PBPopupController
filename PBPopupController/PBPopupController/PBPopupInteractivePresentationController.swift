//
//  PBPopupInteractivePresentationController.swift
//  PBPopupController
//
//  Created by Patrick BODET on 01/07/2018.
//  Copyright © 2018-2021 Patrick BODET. All rights reserved.
//

import UIKit

protocol PBPopupInteractivePresentationDelegate : AnyObject
{
    func presentInteractive()
    func dismissInteractive()
}

internal class PBPopupInteractivePresentationController: UIPercentDrivenInteractiveTransition
{
    private var isPresenting: Bool!
    
    // Set by own when scroll view is at the top (see contentOffset), also when view is not a scroll view.
    private var isDismissing: Bool!
    
    private weak var view: UIView!
    private weak var popupController: PBPopupController!
    
    // Set by popupController when didOpen.
    internal var contentOffset: CGPoint!
    
    internal var gesture: UIPanGestureRecognizer!
    
    private var animator: UIViewPropertyAnimator!
    
    private var progress: CGFloat = 0
    private var location: CGFloat = 0
    
    private var shouldComplete = false
    
    internal weak var delegate: PBPopupInteractivePresentationDelegate?
    
    private var presentationController: PBPopupPresentationController!
    {
        return popupController.popupPresentationController
    }
    
    func attachToViewController(popupController: PBPopupController, withView view: UIView, presenting: Bool)
    {
        self.popupController = popupController
        self.view = view
        
        self.gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(gesture:)))
        self.gesture.delegate = self
        view.addGestureRecognizer(self.gesture)
        if presenting {
            self.popupController.popupBarPanGestureRecognizer = self.gesture
        }
        else {
            self.popupController.popupContentPanGestureRecognizer = self.gesture
        }
        self.isPresenting = presenting
        self.isDismissing = false
    }
    
    deinit
    {
        PBLog("deinit \(self)")
    }
    
    override func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning)
    {
        self.animator = self.presentationController.interruptibleAnimator(using: transitionContext) as? UIViewPropertyAnimator
    }
    
    override var completionSpeed: CGFloat
    {
        get {
            return 1
        }
        set {
            super.completionSpeed = newValue
        }
    }
    
    @objc private func handlePanGesture(gesture: UIPanGestureRecognizer)
    {
        guard let vc = self.popupController.containerViewController else { return }
        
        let translation = gesture.translation(in: gesture.view?.superview)
        let availableHeight: CGFloat = self._popupContainerViewAvailableHeight()
        
        if !self.isPresenting {
            if let scrollView = vc.popupContentViewController.view as? UIScrollView {
                if scrollView.contentOffset.y <= self.contentOffset.y {
                    if !self.isDismissing {
                        self.isDismissing = true
                        self.delegate?.dismissInteractive()
                        gesture.setTranslation(.zero, in: gesture.view?.superview)
                    }
                }
            }
        }
        
        switch gesture.state {
        case .began:
            self.progress = 0.0
            self.location = 0.0
            self.shouldComplete = false
            
            if self.isPresenting {
                self.delegate?.presentInteractive()
            }
            else {
                if !self.isDismissing {
                    if !(vc.popupContentViewController.view is UIScrollView) {
                        self.isDismissing = true
                        self.delegate?.dismissInteractive()
                    }
                }
            }
            self.location = vc.popupContentView.frame.minY + translation.y
            
        case .changed:
            if self.isDismissing, let scrollView = vc.popupContentViewController.view as? UIScrollView {
                scrollView.contentOffset = self.contentOffset
            }
            
            self.progress = translation.y / availableHeight
            
            if self.isPresenting {
                let alpha = (0.30 - self.progress) / 0.30
                self.presentationController.popupBarForPresentation?.alpha = alpha
                vc.popupContentView.popupCloseButton?.alpha = (self.progress - 0.30) / 0.70
            }
            
            if (self.progress >= 1 || self.progress <= 0) {
                self.progress = self.progress >= 1 ? 1 : 0
            }
            
            if let animator = self.animator {
                animator.fractionComplete = self.progress
                self.update(self.progress)
            }
            self.popupController.delegate?.popupController?(self.popupController, interactivePresentationFor: vc.popupContentViewController, state: popupController.popupPresentationState, progress: self.progress, location: self.location + translation.y)
            
            switch gesture.direction {
            case .up:
                self.popupController.popupStatusBarStyle = self.popupController.popupPreferredStatusBarStyle
            case .down:
                self.popupController.popupStatusBarStyle = self.popupController.containerPreferredStatusBarStyle
            default:
                break
            }
            UIView.animate(withDuration: 0.25, delay: 0.0, usingSpringWithDamping: 500, initialSpringVelocity: 0, options: []) {
                vc.setNeedsStatusBarAppearanceUpdate()
            }
            
        case .ended, .cancelled:
            guard let animator = self.animator else { return }
            
            self.shouldComplete = self.completionPosition() == .end
            
            if self.shouldComplete {
                if self.isPresenting {
                    self.popupController.popupStatusBarStyle = self.popupController.popupPreferredStatusBarStyle
                    animator.addAnimations {
                        vc.setNeedsStatusBarAppearanceUpdate()
                        vc.popupContentView.popupCloseButton?.alpha = 1.0
                    }
                    animator.continueAnimation(withTimingParameters: nil, durationFactor: 0)
                    
                    self.presentationController.popupBarForPresentation?.alpha = 0.0
                    self.popupController.popupPresentationState = .opening
                    self.popupController.delegate?.popupController?(self.popupController, stateChanged: self.popupController.popupPresentationState, previousState: .closed)
                    self.popupController.delegate?.popupController?(self.popupController, willOpen: vc.popupContentViewController)
                }
                else {
                    self.popupController.popupStatusBarStyle = self.popupController.containerPreferredStatusBarStyle
                    animator.addAnimations {
                        vc.setNeedsStatusBarAppearanceUpdate()
                    }
                    self.popupController.popupPresentationState = .closing
                    self.popupController.delegate?.popupController?(self.popupController, stateChanged: self.popupController.popupPresentationState, previousState: .open)
                    
                    self.popupController.delegate?.popupController?(self.popupController, willClose: vc.popupContentViewController)
                    self.endInteractiveTransition(with: gesture)
                }
                self.finish()
            }
            else {
                self.cancel()
                animator.isReversed = true
                if self.isPresenting {
                    self.popupController.popupStatusBarStyle = self.popupController.containerPreferredStatusBarStyle
                    animator.addAnimations {
                        vc.setNeedsStatusBarAppearanceUpdate()
                        self.presentationController.popupBarForPresentation?.alpha = 1.0
                    }
                    animator.continueAnimation(withTimingParameters: nil, durationFactor: 0.0)
                }
                else {
                    self.popupController.popupStatusBarStyle = self.popupController.popupPreferredStatusBarStyle
                    if self.isDismissing {
                        animator.addAnimations {
                            vc.setNeedsStatusBarAppearanceUpdate()
                            vc.popupContentView.popupCloseButton?.setButtonStateStationary()
                        }
                        if let scrollView = vc.popupContentViewController.view as? UIScrollView {

                            animator.addCompletion { (_) in
                                scrollView.contentOffset = self.contentOffset
                            }
                        }
                        animator.continueAnimation(withTimingParameters: nil, durationFactor: 0.0)
                    }
                }
            }
            self.isDismissing = false
            break
            
        default:
            break
        }
    }
    
    private func endInteractiveTransition(with gesture: UIPanGestureRecognizer)
    {
        self.presentationController.continueDismissalTransitionWithTimingParameters(nil, durationFactor: 0.5)
    }
    
    private func completionPosition() -> UIViewAnimatingPosition
    {
        guard let vc = self.popupController.containerViewController else { return .current}
        let velocity = self.gesture.velocity(in: gesture.view?.superview).vector
        let isFlick = (velocity.magnitude > vc.popupContentView.popupCompletionFlickMagnitude)
        let isFlickDown = isFlick && (velocity.dy > 0.0)
        let isFlickUp = isFlick && (velocity.dy < 0.0)
        
        if (self.isPresenting == true && isFlickUp) || (self.isDismissing && isFlickDown) {
            return .end
        } else if (self.isPresenting == true && isFlickDown) || (self.isDismissing && isFlickUp) {
            return .start
        } else if self.animator.fractionComplete > vc.popupContentView.popupCompletionThreshold {
            return .end
        } else {
            return .start
        }
    }
    
    private func _popupContainerViewAvailableHeight() -> CGFloat
    {
        guard let vc = self.popupController.containerViewController else { return 0.0 }
        var availableHeight = vc.view.frame.size.height - vc.popupBar.frame.size.height - (vc.bottomBar.isHidden ? 0.0 : vc.bottomBar.frame.size.height)
        if vc.popupContentView.popupPresentationStyle == .custom {
            availableHeight = vc.popupContentView.popupContentSize.height - vc.popupBar.frame.size.height - (vc.bottomBar.isHidden ? 0.0 : vc.bottomBar.frame.size.height)
        }
        availableHeight -= vc.insetsForBottomBar().bottom
        
        let state = self.popupController.popupPresentationState
        return (state == .open || state == .closing ? availableHeight : -availableHeight)
    }
}

extension PBPopupInteractivePresentationController: UIGestureRecognizerDelegate
{
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    {
        let state = self.popupController.popupPresentationState
        if state == .closed && gesture.direction == .down { return false }
        if state == .open && gesture.direction == .up { return false }
        if gesture.direction == .right || gesture.direction == .left { return false }
        
        if self.popupController.delegate?.popupControllerPanGestureShouldBegin?(self.popupController, state: self.popupController.popupPresentationState) == false
        {
            return false
        }
        
        let gesture = gestureRecognizer as! UIPanGestureRecognizer
        if self.isPresenting && gesture.direction != .up
        {
            return false
        }
        let vc = self.popupController.containerViewController
        if !self.isPresenting && !(vc?.popupContentViewController.view is UIScrollView) && gesture.direction != .down
        {
            return false
        }
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        if NSStringFromClass(type(of: otherGestureRecognizer.view!).self).contains("DropShadow") {
            otherGestureRecognizer.state = UIGestureRecognizer.State.failed
            return true
        }
        return true
    }
}

private extension UIPanGestureRecognizer
{
    enum PanDirection: Int
    {
        case up, down, left, right
        var isVertical: Bool {
            return [.up, .down].contains(self)
        }
        var isHorizontal: Bool {
            return !isVertical
        }
    }
    
    var direction: PanDirection?
    {
        let velocity = self.velocity(in: view)
        let isVertical = abs(velocity.y) > abs(velocity.x)
        
        switch (isVertical, velocity.x, velocity.y) {
        case (true, _, let y) where y < 0:
            return .up
        case (true, _, let y) where y > 0:
            return .down
        case (false, let x, _) where x > 0:
            return .right
        case (false, let x, _) where x < 0:
            return .left
        default:
            return nil
        }
    }
}
