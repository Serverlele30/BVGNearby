#import "CardTableViewController.h"

@interface SearchViewController : CardTableViewController
// Gesetzt = Auswahlmodus (z.B. fuer den Routenplaner): Tippen liefert den Ort zurueck.
// stop == nil bedeutet "Mein Standort" (nur wenn offerCurrentLocation gesetzt ist).
@property (nonatomic, copy) void (^pickHandler)(NSDictionary *stop);
// im Auswahlmodus auch Adressen anbieten (z.B. fuer "Zuhause")
@property (nonatomic, assign) BOOL allowAddresses;
// im Auswahlmodus "Mein Standort" sowie Zuhause/Arbeit als Schnellauswahl zeigen
@property (nonatomic, assign) BOOL offerCurrentLocation;
@property (nonatomic, assign) BOOL offerSavedPlaces;
@property (nonatomic, copy) NSString *pickTitle;   // z.B. "Start" / "Ziel"
@end
