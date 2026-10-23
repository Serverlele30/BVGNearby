#import "CardCell.h"
#import "BVGTheme.h"

#pragma mark - Hintergrund der Karte

@interface CardBackgroundView : UIView
@property (nonatomic, strong) UIColor *fillColor;
@property (nonatomic, assign) BOOL roundTop;
@property (nonatomic, assign) BOOL roundBottom;
@property (nonatomic, assign) BOOL separator;
@end

@implementation CardBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    UIRectCorner corners = 0;
    if (self.roundTop)    corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
    if (self.roundBottom) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
    CGFloat r = [BVGTheme cardRadius];
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:self.bounds byRoundingCorners:corners cornerRadii:CGSizeMake(r, r)];
    [(self.fillColor ?: [BVGTheme card]) setFill];
    [p fill];

    if (self.separator) {
        CGFloat h = 1.0 / [UIScreen mainScreen].scale;
        [[BVGTheme separator] setFill];
        UIRectFill(CGRectMake(16, self.bounds.size.height - h, self.bounds.size.width - 16, h));
    }
}

@end

#pragma mark - Zelle

@implementation CardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.backgroundView = [[CardBackgroundView alloc] init];
        self.selectedBackgroundView = [[CardBackgroundView alloc] init];
        self.textLabel.font = [BVGTheme font:16 weight:UIFontWeightRegular];
        self.textLabel.textColor = [BVGTheme textPrimary];
        self.detailTextLabel.font = [BVGTheme font:14 weight:UIFontWeightRegular];
        self.detailTextLabel.textColor = [BVGTheme textSecondary];
        self.firstInSection = YES;
        self.lastInSection = YES;
        [self applyCardStyle];
    }
    return self;
}

// der eigentliche Trick: Zelle seitlich einruecken -> Karten-Optik wie ab iOS 13
- (void)setFrame:(CGRect)frame {
    CGFloat inset = [BVGTheme cardInset];
    if (frame.size.width > 2 * inset + 100) {
        frame.origin.x += inset;
        frame.size.width -= 2 * inset;
    }
    [super setFrame:frame];
}

- (void)setCardColor:(UIColor *)cardColor {
    _cardColor = cardColor;
    [self applyCardStyle];
}

- (void)applyCardStyle {
    CardBackgroundView *bg = (CardBackgroundView *)self.backgroundView;
    CardBackgroundView *sel = (CardBackgroundView *)self.selectedBackgroundView;
    if (![bg isKindOfClass:[CardBackgroundView class]] || ![sel isKindOfClass:[CardBackgroundView class]]) return;

    bg.fillColor = self.cardColor ?: [BVGTheme card];
    sel.fillColor = [BVGTheme cardPressed];
    for (CardBackgroundView *v in @[bg, sel]) {
        v.roundTop = self.firstInSection;
        v.roundBottom = self.lastInSection;
        v.separator = !self.lastInSection;
        [v setNeedsDisplay];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.cardColor = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.accessoryView = nil;
    self.imageView.image = nil;
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
    self.textLabel.font = [BVGTheme font:16 weight:UIFontWeightRegular];
    self.textLabel.textColor = [BVGTheme textPrimary];
    self.textLabel.textAlignment = NSTextAlignmentLeft;
    self.detailTextLabel.font = [BVGTheme font:14 weight:UIFontWeightRegular];
    self.detailTextLabel.textColor = [BVGTheme textSecondary];
    self.contentView.alpha = 1;
}

@end
