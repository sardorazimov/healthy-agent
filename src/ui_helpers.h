#ifndef UI_HELPERS_H
#define UI_HELPERS_H

#import <Cocoa/Cocoa.h>

// Re-resolves an NSColor to a CGColor under the view's effective appearance
// and assigns it to the layer. Needed because NSColor.CGColor snapshots
// against NSAppearance.currentAppearance, which is not automatically the
// view's appearance at the time viewDidChangeEffectiveAppearance fires.
NS_INLINE void m_set_layer_bg(CALayer *layer, NSColor *color, NSView *view) {
    if (!layer || !color || !view) return;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
        layer.backgroundColor = color.CGColor;
    }];
}

// Runs an arbitrary block with the view's effective appearance as the
// current drawing appearance — use when multiple CGColor resolutions or
// other appearance-sensitive operations happen together.
NS_INLINE void m_with_view_appearance(NSView *view, void (^block)(void)) {
    if (!view || !block) return;
    [view.effectiveAppearance performAsCurrentDrawingAppearance:block];
}

#endif
