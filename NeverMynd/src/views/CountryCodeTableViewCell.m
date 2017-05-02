#import "CountryCodeTableViewCell.h"

@implementation CountryCodeTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

- (void)configureWithCountryCode:(NSString *)code andCountryName:(NSString *)name {
    _countryNameLabel.text = [NSString stringWithFormat:@"%@ (%@)", name, code ] ;
}

@end
