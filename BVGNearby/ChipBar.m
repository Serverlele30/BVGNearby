#import "ChipBar.h"
#import "BVGTheme.h"

@interface ChipBar ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) NSArray *buttons;
@end

@implementation ChipBar

- (instancetype)initWithItems:(NSArray *)titles {
    self = [super initWithFrame:CGRectMake(0, 0, 320, 44)];
    if (self) {
        _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scroll.showsHorizontalScrollIndicator = NO;
        [self addSubview:_scroll];

        NSMutableArray *buttons = [NSMutableArray array];
        CGFloat x = [BVGTheme cardInset];
        for (NSUInteger i = 0; i < titles.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            [b setTitle:titles[i] forState:UIControlStateNormal];
            b.titleLabel.font = [BVGTheme font:14 weight:UIFontWeightMedium];
            CGFloat w = ceil([titles[i] sizeWithAttributes:@{ NSFontAttributeName: b.titleLabel.font }].width) + 24;
            b.frame = CGRectMake(x, 7, w, 30);
            b.layer.cornerRadius = 15;
            b.tag = i;
            [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:b];
            [buttons addObject:b];
            x += w + 8;
        }
        _scroll.contentSize = CGSizeMake(x + [BVGTheme cardInset] - 8, 44);
        _buttons = buttons;
        [self refresh];
    }
    return self;
}

- (void)tapped:(UIButton *)b {
    if (b.tag == self.selectedIndex) return;
    self.selectedIndex = b.tag;
    if (self.onChange) self.onChange(b.tag);
}

- (void)setIdleColor:(UIColor *)idleColor {
    _idleColor = idleColor;
    [self refresh];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self refresh];
}

- (void)refresh {
    for (UIButton *b in self.buttons) {
        BOOL on = b.tag == self.selectedIndex;
        [UIView animateWithDuration:0.15 animations:^{
            b.backgroundColor = on ? [BVGTheme textPrimary] : (self.idleColor ?: [BVGTheme card]);
        }];
        [b setTitleColor:(on ? [UIColor whiteColor] : [BVGTheme textPrimary]) forState:UIControlStateNormal];
        b.accessibilityTraits = UIAccessibilityTraitButton | (on ? UIAccessibilityTraitSelected : 0);
    }
}

@end
