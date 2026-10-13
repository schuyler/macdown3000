#import <Foundation/Foundation.h>
#import "JJPluralForm.h"

// Exercise the actual application resources with the actual plural formatter.
// Explicit expected forms are independent of the strings under test.
int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        NSArray *locales = @[@"ru-RU", @"uk", @"cs", @"sk"];
        NSArray *words = @[@[@"слово", @"слова", @"слов"],
                           @[@"слово", @"слова", @"слів"],
                           @[@"slovo", @"slova", @"slov"],
                           @[@"slovo", @"slová", @"slov"]];
        NSArray *characters = @[@[@"символ", @"символа", @"символов"],
                                @[@"символ", @"символи", @"символів"],
                                @[@"znak", @"znaky", @"znaků"],
                                @[@"znak", @"znaky", @"znakov"]];
        NSArray *selectedWords = @[@[@"выделенное слово", @"выделенных слова", @"выделенных слов"],
                                   @[@"виділене слово", @"виділені слова", @"виділених слів"],
                                   @[@"vybrané slovo", @"vybraná slova", @"vybraných slov"],
                                   @[@"vybrané slovo", @"vybrané slová", @"vybraných slov"]];
        NSArray *selectedCharacters = @[@[@"выделенный символ", @"выделенных символа", @"выделенных символов"],
                                        @[@"виділений символ", @"виділені символи", @"виділених символів"],
                                        @[@"vybraný znak", @"vybrané znaky", @"vybraných znaků"],
                                        @[@"vybraný znak", @"vybrané znaky", @"vybraných znakov"]];
        NSArray *suffixes = @[@" (без пробелов)", @" (без пробілів)", @" (bez mezer)", @" (bez medzier)"];
        NSArray *keys = @[@"WORDS_PLURAL_STRING", @"CHARACTERS_PLURAL_STRING",
                          @"CHARACTERS_NO_SPACES_PLURAL_STRING", @"WORDS_SELECTED_PLURAL_STRING",
                          @"CHARACTERS_SELECTED_PLURAL_STRING", @"CHARACTERS_NO_SPACES_SELECTED_PLURAL_STRING"];
        // Each row is count, Russian/Ukrainian expected form, Czech/Slovak form.
        NSArray *cases = @[@[@0,@2,@2], @[@1,@0,@0], @[@2,@1,@1], @[@4,@1,@1],
                           @[@5,@2,@2], @[@11,@2,@2], @[@12,@2,@2], @[@14,@2,@2],
                           @[@21,@0,@2], @[@22,@1,@2], @[@24,@1,@2], @[@25,@2,@2],
                           @[@101,@0,@2], @[@111,@2,@2], @[@112,@2,@2]];
        NSUInteger failures = 0, checks = 0;
        for (NSUInteger locale = 0; locale < locales.count; locale++) {
            NSString *path = [root stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@.lproj/Localizable.strings", locales[locale]]];
            NSDictionary *strings = [NSDictionary dictionaryWithContentsOfFile:path];
            if (!strings) { NSLog(@"Cannot load %@", path); return 2; }
            JJPluralRule rule = [strings[@"JJ_PLURAL_FORM_RULE"] integerValue];
            for (NSArray *row in cases) {
                NSUInteger count = [row[0] unsignedIntegerValue];
                NSUInteger form = [row[locale < 2 ? 1 : 2] unsignedIntegerValue];
                NSArray *expectedForms = @[words[locale], characters[locale], characters[locale],
                                           selectedWords[locale], selectedCharacters[locale], selectedCharacters[locale]];
                for (NSUInteger key = 0; key < keys.count; key++) {
                    NSString *suffix = (key == 2 || key == 5) ? suffixes[locale] : @"";
                    NSString *expected = [NSString stringWithFormat:@"%lu %@%@",
                        (unsigned long)count, expectedForms[key][form], suffix];
                    NSString *actual = [JJPluralForm pluralStringForNumber:count
                        withPluralForms:strings[keys[key]] usingPluralRule:rule localizeNumeral:NO];
                    checks++;
                    if (![actual isEqualToString:expected]) {
                        NSLog(@"%@ %@ count %@: expected '%@', got '%@'", locales[locale], keys[key], row[0], expected, actual);
                        failures++;
                    }
                }
            }
        }
        NSLog(@"Plural counts: %lu checks, %lu failures", (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
