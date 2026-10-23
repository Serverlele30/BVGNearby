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
        self.detailTextLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
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
    self.detailTextLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
    self.detailTextLabel.textColor = [BVGTheme textSecondary];
    self.contentView.alpha = 1;
}

@end

#pragma mark - Mehrzeilige Zelle mit selbst berechneter Hoehe

@implementation InfoCell

static const CGFloat kPadV = 10, kPadH = 12, kGap = 10, kLineGap = 3;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeLeft;
        [self.contentView addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.numberOfLines = 0;
        _titleLabel.font = [BVGTheme font:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [BVGTheme textPrimary];
        [self.contentView addSubview:_titleLabel];

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.numberOfLines = 0;
        _detailLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
        _detailLabel.textColor = [BVGTheme textSecondary];
        [self.contentView addSubview:_detailLabel];
    }
    return self;
}

- (CGFloat)iconWidth {
    UIImage *img = self.iconView.image;
    return img ? MIN(MAX(img.size.width, 24), 64) : 0;
}

- (CGFloat)textX {
    CGFloat iw = [self iconWidth];
    return kPadH + (iw ? iw + kGap : 0);
}

+ (CGFloat)heightOfLabel:(UILabel *)l width:(CGFloat)w {
    if (!l.text.length && !l.attributedText.length) return 0;
    if (w <= 0) return 0;
    return ceil([l sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)].height);
}

// Breite fuer den Text bei gegebener Tabellenbreite (Karten-Einrueckung + Pfeil rechts beruecksichtigt)
- (CGFloat)textWidthForContentWidth:(CGFloat)cw {
    return cw - [self textX] - kPadH;
}

- (CGFloat)heightForTextWidth:(CGFloat)tw {
    CGFloat th = [InfoCell heightOfLabel:self.titleLabel width:tw];
    CGFloat dh = [InfoCell heightOfLabel:self.detailLabel width:tw];
    CGFloat h = kPadV + th + (th && dh ? kLineGap : 0) + dh + kPadV;
    CGFloat iconH = self.iconView.image ? self.iconView.image.size.height + 2 * kPadV : 0;
    return ceil(MAX(MAX(h, iconH), 44));
}

- (CGFloat)fittingHeightForTableWidth:(CGFloat)tableWidth {
    CGFloat cw = tableWidth - 2 * [BVGTheme cardInset];
    if (self.accessoryType != UITableViewCellAccessoryNone || self.accessoryView) cw -= 40;   // Pfeil/Schalter (lieber etwas zu viel Platz als abgeschnitten)
    return [self heightForTextWidth:[self textWidthForContentWidth:cw]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat tw = [self textWidthForContentWidth:w];
    CGFloat th = [InfoCell heightOfLabel:self.titleLabel width:tw];
    CGFloat dh = [InfoCell heightOfLabel:self.detailLabel width:tw];
    CGFloat total = th + (th && dh ? kLineGap : 0) + dh;
    CGFloat y = MAX(kPadV, floor((h - total) / 2));   // vertikal mittig

    CGFloat iw = [self iconWidth];
    if (iw) {
        CGFloat ih = self.iconView.image.size.height;
        self.iconView.frame = CGRectMake(kPadH, floor((h - ih) / 2), iw, ih);
    }
    self.titleLabel.frame = CGRectMake([self textX], y, tw, th);
    self.detailLabel.frame = CGRectMake([self textX], y + th + (th && dh ? kLineGap : 0), tw, dh);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
    self.titleLabel.attributedText = nil;
    self.titleLabel.text = nil;
    self.detailLabel.text = nil;
    self.titleLabel.font = [BVGTheme font:15 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [BVGTheme textPrimary];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.detailLabel.font = [BVGTheme font:13 weight:UIFontWeightRegular];
    self.detailLabel.textColor = [BVGTheme textSecondary];
}

@end
