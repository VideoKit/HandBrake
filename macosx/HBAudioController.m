//
//  HBAudioController.m
//  HandBrake
//
//  Created on 2010-08-24.
//

#import "HBAudioController.h"
#import "Controller.h"
#import "HBAudio.h"
#import "hb.h"

NSString *keyAudioTrackIndex = @"keyAudioTrackIndex";
NSString *keyAudioTrackName = @"keyAudioTrackName";
NSString *keyAudioInputBitrate = @"keyAudioInputBitrate";
NSString *keyAudioInputSampleRate = @"keyAudioInputSampleRate";
NSString *keyAudioInputCodec = @"keyAudioInputCodec";
NSString *keyAudioInputCodecParam = @"keyAudioInputCodecParam";
NSString *keyAudioInputChannelLayout = @"keyAudioInputChannelLayout";
NSString *HBMixdownChangedNotification = @"HBMixdownChangedNotification";


@interface HBAudioController () {
    /* New Audio Auto Passthru box */
    IBOutlet NSBox               * fAudioAutoPassthruBox;
    IBOutlet NSPopUpButton       * fAudioFallbackPopUp;

    IBOutlet NSTableView         * fTableView;
    IBOutlet NSButton            * fAddAllTracksButton;

    id                             myController;
    NSMutableArray               * audioArray;        // the configured audio information
    NSArray                      * masterTrackArray;  // the master list of audio tracks from the title
    NSDictionary                 * noneTrack;         // this represents no audio track selection
    NSNumber                     * videoContainerTag; // initially is the default HB_MUX_MP4
}

@property (nonatomic, readwrite, retain) NSArray *masterTrackArray;
@property (nonatomic, retain) NSNumber *videoContainerTag;

- (void) addAllTracksFromPreset: (NSMutableDictionary *) aPreset;
- (IBAction) addAllAudioTracks: (id) sender;
- (void) addNewAudioTrack;

@end // interface HBAudioController


@implementation HBAudioController

#pragma mark -
#pragma mark Accessors

@synthesize masterTrackArray;
@synthesize noneTrack;
@synthesize videoContainerTag;

- (NSString *)audioEncoderFallback
{
    return [[fAudioFallbackPopUp selectedItem] title];
}

- (void)setAudioEncoderFallback:(NSString *)string
{
    [fAudioFallbackPopUp selectItemWithTitle:string];
}

- (NSInteger)audioEncoderFallbackTag
{
    return [[fAudioFallbackPopUp selectedItem] tag];
}

- (void)setAudioEncoderFallbackTag:(NSInteger)tag
{
    [fAudioFallbackPopUp selectItemWithTag:tag];
}

- (instancetype)init
{
    self = [super initWithNibName:@"Audio" bundle:nil];
    if (self)
    {
        [self setVideoContainerTag: [NSNumber numberWithInt: HB_MUX_MP4]];
        audioArray = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void) dealloc

{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [masterTrackArray release];
    [noneTrack release];
    [audioArray release];
    [self setVideoContainerTag: nil];
    [super dealloc];
}

- (void) setHBController: (id) aController

{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    myController = aController;

    /* register that we are interested in changes made to the video container */
    [center addObserver: self selector: @selector(containerChanged:) name: HBContainerChangedNotification object: aController];
    [center addObserver: self selector: @selector(titleChanged:) name: HBTitleChangedNotification object: aController];
}

- (void) _clearAudioArray

{
    while (0 < [self countOfAudioArray])
    {
        [self removeObjectFromAudioArrayAtIndex: 0];
    }
}


- (IBAction) addAllAudioTracks: (id) sender
{
    [self addAllTracksFromPreset:[myController selectedPreset]];
    return;
}

- (void)enableUI:(BOOL)b
{
    [fTableView setEnabled:b];
    [fAddAllTracksButton setEnabled:b];
    [fAudioFallbackPopUp setEnabled:b];
}

#pragma mark -
#pragma mark HBController Support

- (void) prepareAudioForQueueFileJob: (NSMutableDictionary *) aDict

{
    NSUInteger audioArrayCount = [self countOfAudioArray];
    for (NSUInteger counter = 0; counter < audioArrayCount; counter++)
    {
        HBAudio *anAudio = [self objectInAudioArrayAtIndex: counter];
        if ([anAudio enabled])
        {
            NSString *prefix = [NSString stringWithFormat: @"Audio%lu", counter + 1];
            NSNumber *sampleRateToUse = ([[[anAudio sampleRate] objectForKey: keyAudioSamplerate] intValue] == 0 ?
                                         [[anAudio track] objectForKey: keyAudioInputSampleRate] :
                                         [[anAudio sampleRate] objectForKey: keyAudioSamplerate]);

            [aDict setObject: [[anAudio track] objectForKey: keyAudioTrackIndex] forKey: [prefix stringByAppendingString: @"Track"]];
            [aDict setObject: [[anAudio track] objectForKey: keyAudioTrackName] forKey: [prefix stringByAppendingString: @"TrackDescription"]];
            [aDict setObject: [[anAudio codec] objectForKey: keyAudioCodecName] forKey: [prefix stringByAppendingString: @"Encoder"]];
            [aDict setObject: [[anAudio mixdown] objectForKey: keyAudioMixdownName] forKey: [prefix stringByAppendingString: @"Mixdown"]];
            [aDict setObject: [[anAudio sampleRate] objectForKey: keyAudioSampleRateName] forKey: [prefix stringByAppendingString: @"Samplerate"]];
            [aDict setObject: [[anAudio bitRate] objectForKey: keyAudioBitrateName] forKey: [prefix stringByAppendingString: @"Bitrate"]];

            // output is not passthru so apply gain
            if (!([[[anAudio codec] objectForKey: keyAudioCodec] intValue] & HB_ACODEC_PASS_FLAG))
            {
                [aDict setObject: [anAudio gain] forKey: [prefix stringByAppendingString: @"TrackGainSlider"]];
            }
            else
            {
                // output is passthru - the Gain dial is disabled so don't apply its value
                [aDict setObject: [NSNumber numberWithInt:0] forKey: [prefix stringByAppendingString: @"TrackGainSlider"]];
            }

            if (hb_audio_can_apply_drc([[[anAudio track] objectForKey: keyAudioInputCodec] intValue],
                                       [[[anAudio track] objectForKey: keyAudioInputCodecParam] intValue],
                                       [[[anAudio codec] objectForKey: keyAudioCodec] intValue]))
            {
                [aDict setObject: [anAudio drc] forKey: [prefix stringByAppendingString: @"TrackDRCSlider"]];
            }
            else
            {
                // source isn't AC3 or output is passthru - the DRC dial is disabled so don't apply its value
                [aDict setObject: [NSNumber numberWithInt:0] forKey: [prefix stringByAppendingString: @"TrackDRCSlider"]];
            }

            prefix = [NSString stringWithFormat: @"JobAudio%lu", counter + 1];
            [aDict setObject: [[anAudio codec] objectForKey: keyAudioCodec] forKey: [prefix stringByAppendingString: @"Encoder"]];
            [aDict setObject: [[anAudio mixdown] objectForKey: keyAudioMixdown] forKey: [prefix stringByAppendingString: @"Mixdown"]];
            [aDict setObject: sampleRateToUse forKey: [prefix stringByAppendingString: @"Samplerate"]];
            [aDict setObject: [[anAudio bitRate] objectForKey: keyAudioBitrate] forKey: [prefix stringByAppendingString: @"Bitrate"]];
        }
    }
}

- (void) prepareAudioForJobPreview: (hb_job_t *) aJob

{
    unsigned int i;

    // First clear out any audio tracks in the job currently
    int audiotrack_count = hb_list_count(aJob->list_audio);
    for(i = 0; i < audiotrack_count; i++)

    {
        hb_audio_t *temp_audio = (hb_audio_t *) hb_list_item(aJob->list_audio, 0);
        hb_list_rem(aJob->list_audio, temp_audio);
    }

    // Now add audio tracks based on the current settings
    NSUInteger audioArrayCount = [self countOfAudioArray];
    for (i = 0; i < audioArrayCount; i++)
    {
        HBAudio *anAudio = [self objectInAudioArrayAtIndex:i];
        if ([anAudio enabled])
        {
            NSNumber *sampleRateToUse = ([[[anAudio sampleRate] objectForKey:keyAudioSamplerate] intValue] == 0 ?
                                         [[anAudio track]       objectForKey:keyAudioInputSampleRate] :
                                         [[anAudio sampleRate]  objectForKey:keyAudioSamplerate]);

            hb_audio_config_t *audio = (hb_audio_config_t*)calloc(1, sizeof(*audio));
            hb_audio_config_init(audio);
            audio->in.track          = [[[anAudio track] objectForKey:keyAudioTrackIndex] intValue] - 1;
            /* We go ahead and assign values to our audio->out.<properties> */
            audio->out.track                     = audio->in.track;
            audio->out.codec                     = [[[anAudio codec]   objectForKey:keyAudioCodec]   intValue];
            audio->out.compression_level         = hb_audio_compression_get_default(audio->out.codec);
            audio->out.mixdown                   = [[[anAudio mixdown] objectForKey:keyAudioMixdown] intValue];
            audio->out.normalize_mix_level       = 0;
            audio->out.bitrate                   = [[[anAudio bitRate] objectForKey:keyAudioBitrate] intValue];
            audio->out.samplerate                = [sampleRateToUse  intValue];
            audio->out.dynamic_range_compression = [[anAudio drc]  floatValue];
            audio->out.gain                      = [[anAudio gain] floatValue];
            audio->out.dither_method             = hb_audio_dither_get_default();

            hb_audio_add(aJob, audio);
            free(audio);
        }
    }
}

- (void) prepareAudioForPreset: (NSMutableArray *) anArray

{
    NSUInteger audioArrayCount = [self countOfAudioArray];
    NSUInteger i;

    for (i = 0; i < audioArrayCount; i++)
    {
        HBAudio *anAudio = [self objectInAudioArrayAtIndex: i];
        if ([anAudio enabled])
        {
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity: 7];
            [dict setObject: [[anAudio track] objectForKey: keyAudioTrackIndex] forKey: @"AudioTrack"];
            [dict setObject: [[anAudio track] objectForKey: keyAudioTrackName] forKey: @"AudioTrackDescription"];
            [dict setObject: [[anAudio codec] objectForKey: keyAudioCodecName] forKey: @"AudioEncoder"];
            [dict setObject: [[anAudio mixdown] objectForKey: keyAudioMixdownName] forKey: @"AudioMixdown"];
            [dict setObject: [[anAudio sampleRate] objectForKey: keyAudioSampleRateName] forKey: @"AudioSamplerate"];
            [dict setObject: [[anAudio bitRate] objectForKey: keyAudioBitrateName] forKey: @"AudioBitrate"];
            [dict setObject: [anAudio drc] forKey: @"AudioTrackDRCSlider"];
            [dict setObject: [anAudio gain] forKey: @"AudioTrackGainSlider"];
            [anArray addObject: dict];
            [dict release];
        }
    }
}

- (void) addTracksFromQueue: (NSMutableDictionary *) aQueue

{
    NSString *base;
    int value;
    int maximumNumberOfAllowedAudioTracks = [HBController maximumNumberOfAllowedAudioTracks];

    // Reinitialize the configured list of audio tracks
    [self _clearAudioArray];

    // The following is the pattern to follow, but with Audio%dTrack being the key to seek...
    // Can we assume that there will be no skip in the data?
    for (unsigned int i = 1; i <= maximumNumberOfAllowedAudioTracks; i++)
    {
        base = [NSString stringWithFormat: @"Audio%d", i];
        value = [[aQueue objectForKey: [base stringByAppendingString: @"Track"]] intValue];
        if (0 < value)
        {
            HBAudio *newAudio = [[HBAudio alloc] init];
            [newAudio setController: self];
            [self insertObject: newAudio inAudioArrayAtIndex: [self countOfAudioArray]];
            [newAudio setVideoContainerTag: [self videoContainerTag]];
            [newAudio setTrackFromIndex: value];
            [newAudio setCodecFromName: [aQueue objectForKey: [base stringByAppendingString: @"Encoder"]]];
            [newAudio setMixdownFromName: [aQueue objectForKey: [base stringByAppendingString: @"Mixdown"]]];
            [newAudio setSampleRateFromName: [aQueue objectForKey: [base stringByAppendingString: @"Samplerate"]]];
            [newAudio setBitRateFromName: [aQueue objectForKey: [base stringByAppendingString: @"Bitrate"]]];
            [newAudio setDrc: [aQueue objectForKey: [base stringByAppendingString: @"TrackDRCSlider"]]];
            [newAudio setGain: [aQueue objectForKey: [base stringByAppendingString: @"TrackGainSlider"]]];
            [newAudio release];
        }
    }

    [self switchingTrackFromNone: nil]; // see if we need to add one to the list
}

// This routine takes the preset and will return the value for the key AudioList
// if it exists, otherwise it creates an array from the data in the present.
- (NSArray *) _presetAudioArrayFromPreset: (NSMutableDictionary *) aPreset

{
    NSArray *retval = [aPreset objectForKey: @"AudioList"];

    if (!retval)
    {
        int maximumNumberOfAllowedAudioTracks = [HBController maximumNumberOfAllowedAudioTracks];
        NSString *base;
        NSMutableArray *whatToUse = [NSMutableArray array];
        for (unsigned int i = 1; i <= maximumNumberOfAllowedAudioTracks; i++)
        {
            base = [NSString stringWithFormat: @"Audio%d", i];
            if (nil != [aPreset objectForKey: [base stringByAppendingString: @"Track"]])
            {
                [whatToUse addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       [aPreset objectForKey: [base stringByAppendingString: @"Encoder"]], @"AudioEncoder",
                                       [aPreset objectForKey: [base stringByAppendingString: @"Mixdown"]], @"AudioMixdown",
                                       [aPreset objectForKey: [base stringByAppendingString: @"Samplerate"]], @"AudioSamplerate",
                                       [aPreset objectForKey: [base stringByAppendingString: @"Bitrate"]], @"AudioBitrate",
                                       [aPreset objectForKey: [base stringByAppendingString: @"TrackDRCSlider"]], @"AudioTrackDRCSlider",
                                       [aPreset objectForKey: [base stringByAppendingString: @"TrackGainSlider"]], @"AudioTrackGainSlider",
                                       nil]];
            }
        }
        retval = whatToUse;
    }
    return retval;
}

// This uses the templateAudioArray from the preset to create the audios for the specified trackIndex
- (void) _processPresetAudioArray: (NSArray *) templateAudioArray forTrack: (unsigned int) trackIndex andType: (int) aType

{
    NSEnumerator *enumerator = [templateAudioArray objectEnumerator];
    NSMutableDictionary *dict;
    NSString *key;
    int maximumNumberOfAllowedAudioTracks = [HBController maximumNumberOfAllowedAudioTracks];

    while (nil != (dict = [enumerator nextObject]))
    {
        // copy the dictionary since we may need to alter it
        dict = [NSMutableDictionary dictionaryWithDictionary:dict];

        if ([self countOfAudioArray] < maximumNumberOfAllowedAudioTracks)
        {
            BOOL fallenBack = NO;
            HBAudio *newAudio = [[HBAudio alloc] init];
            [newAudio setController: self];
            [self insertObject: newAudio inAudioArrayAtIndex: [self countOfAudioArray]];
            [newAudio setVideoContainerTag: [self videoContainerTag]];
            [newAudio setTrackFromIndex: trackIndex];

            // map legacy encoder names via libhb
            key = [dict objectForKey:@"AudioEncoder"];
            if (key != nil)
            {
                const char *name;
                // passthru fallbacks
                if ([key hasSuffix:@"Passthru"] &&
                    ![newAudio setCodecFromName:key])
                {
                    int passthru, fallback;
                    fallenBack = YES;
                    passthru   = hb_audio_encoder_get_from_name([key UTF8String]);
                    fallback   = hb_audio_encoder_get_fallback_for_passthru(passthru);
                    name       = hb_audio_encoder_get_name(fallback);
                }
                else
                {
                    name = hb_audio_encoder_sanitize_name([key UTF8String]);
                }
                [dict setObject:[NSString stringWithFormat:@"%s", name]
                         forKey:@"AudioEncoder"];
            }

            // If our preset does not contain a drc or gain value set it to a default of 0.0
            if (![dict objectForKey: @"AudioTrackDRCSlider"])
            {
                [dict setObject:[NSNumber numberWithFloat:0.0] forKey:@"AudioTrackDRCSlider"];
            }
            if (![dict objectForKey: @"AudioTrackGainSlider"])
            {
                [dict setObject:[NSNumber numberWithFloat:0.0] forKey:@"AudioTrackGainSlider"];
            }

            // map legacy mixdowns via libhb
            key = [dict objectForKey: @"AudioMixdown"];
            if (key != nil)
            {
                [dict setObject:[NSString stringWithFormat:@"%s",
                                 hb_mixdown_sanitize_name([key UTF8String])]
                         forKey:@"AudioMixdown"];
            }

            // If our preset wants us to support a codec that the track does not support, instead
            // of changing the codec we remove the audio instead.
            if ([newAudio setCodecFromName: [dict objectForKey: @"AudioEncoder"]])
            {
                [newAudio setMixdownFromName: [dict objectForKey: @"AudioMixdown"]];
                [newAudio setSampleRateFromName: [dict objectForKey: @"AudioSamplerate"]];
                if (!fallenBack)
                {
                    [newAudio setBitRateFromName: [dict objectForKey: @"AudioBitrate"]];
                }
                [newAudio setDrc: [dict objectForKey: @"AudioTrackDRCSlider"]];
                [newAudio setGain: [dict objectForKey: @"AudioTrackGainSlider"]];
            }
            else
            {
                [self removeObjectFromAudioArrayAtIndex: [self countOfAudioArray] - 1];
            }
            [newAudio release];
        }
    }
}

// This matches the FIRST track with the specified prefix, otherwise it uses the defaultIfNotFound value
- (unsigned int) _trackWithTitlePrefix: (NSString *) prefix defaultIfNotFound: (unsigned int) defaultIfNotFound

{
    unsigned int retval = defaultIfNotFound;
    NSUInteger count = [masterTrackArray count];
    NSString *languageTitle;
    BOOL found = NO;

    // We search for the prefix noting that our titles have the format %d: %s where the %s is the prefix
    for (unsigned int i = 1; i < count && !found; i++) // Note that we skip the "None" track
    {
        languageTitle = [[masterTrackArray objectAtIndex: i] objectForKey: keyAudioTrackName];
        if ([[languageTitle substringFromIndex: [languageTitle rangeOfString: @" "].location + 1] hasPrefix: prefix])
        {
            retval = i;
            found = YES;
        }
    }
    return retval;
}

// When we add a track and we do not have a preset to use for the track we use
// this bogus preset to do the dirty work.
- (NSMutableDictionary *) _defaultPreset

{
    static NSMutableDictionary *retval = nil;

    if (!retval)
    {
        retval = [[NSMutableDictionary dictionaryWithObjectsAndKeys:
                   [NSArray arrayWithObject:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSNumber numberWithInt: 1],     @"AudioTrack",
                     @"AAC (CoreAudio)",              @"AudioEncoder",
                     @"Dolby Pro Logic II",           @"AudioMixdown",
                     @"Auto",                         @"AudioSamplerate",
                     @"160",                          @"AudioBitrate",
                     [NSNumber numberWithFloat: 0.0], @"AudioTrackDRCSlider",
                     [NSNumber numberWithFloat: 0.0], @"AudioTrackGainSlider",
                     nil]], @"AudioList", nil] retain];
    }
    return retval;
}

- (void) addTracksFromPreset: (NSMutableDictionary *) aPreset allTracks: (BOOL) allTracks

{
    id whatToUse = [self _presetAudioArrayFromPreset: aPreset];
    NSMutableArray *tracksToAdd = [[NSMutableArray alloc] init];

    NSArray* preferredLanguages = [NSArray arrayWithObjects: 
                          [[NSUserDefaults standardUserDefaults] stringForKey: @"DefaultLanguage"],
                          [[NSUserDefaults standardUserDefaults] stringForKey: @"AlternateLanguage"],
                          nil];

    // Add tracks of Default and Alternate Language by name
    for(id languageName in preferredLanguages)
    {
        int trackNumber = [self _trackWithTitlePrefix: languageName defaultIfNotFound: 0];
        
        if(trackNumber > 0 && [tracksToAdd indexOfObject:[NSNumber numberWithInt:trackNumber]] == NSNotFound)
        {
            [tracksToAdd addObject:[NSNumber numberWithInt:trackNumber]];
        }
    }

    // If no preferred Language was found, add standard track 1
    if([tracksToAdd count] == 0)
    {
        [tracksToAdd addObject:[NSNumber numberWithInt:1]];
    }

    // If all tracks should be added, add all track numbers that are not yet processed
    if (allTracks)
    {
        NSUInteger count = [masterTrackArray count];
        for (unsigned int i = 1; i < count; i++)
        {
            NSNumber *trackNumber = [NSNumber numberWithInt:i];
            if([tracksToAdd indexOfObject:trackNumber] == NSNotFound)
            {
               [tracksToAdd addObject:trackNumber];
            }
        }
    }
         
    // Reinitialize the configured list of audio tracks
    [self _clearAudioArray];

    for(id trackNumber in tracksToAdd)
    {
        [self _processPresetAudioArray: whatToUse forTrack:[trackNumber intValue] andType: [[aPreset objectForKey: @"Type"] intValue]];
    }
    [tracksToAdd release];
}

- (void) _ensureAtLeastOneNonEmptyTrackExists

{
    NSUInteger count = [self countOfAudioArray];
    if (0 == count || ![[self objectInAudioArrayAtIndex: 0] enabled])
    {
        [self addTracksFromPreset: [self _defaultPreset] allTracks: NO];
    }
    [self switchingTrackFromNone: nil]; // this ensures there is a None track at the end of the list
}

- (void) addTracksFromPreset: (NSMutableDictionary *) aPreset

{
    [self addTracksFromPreset: aPreset allTracks: NO];
    [self _ensureAtLeastOneNonEmptyTrackExists];
}

- (void) addAllTracksFromPreset: (NSMutableDictionary *) aPreset

{
    [self addTracksFromPreset: aPreset allTracks: YES];
    [self _ensureAtLeastOneNonEmptyTrackExists];
}

- (BOOL) anyCodecMatches: (int) aCodecValue

{
    BOOL retval = NO;
    NSUInteger audioArrayCount = [self countOfAudioArray];
    for (NSUInteger i = 0; i < audioArrayCount && !retval; i++)
    {
        HBAudio *anAudio = [self objectInAudioArrayAtIndex: i];
        if ([anAudio enabled] && aCodecValue == [[[anAudio codec] objectForKey: keyAudioCodec] intValue])
        {
            retval = YES;
        }
    }
    return retval;
}

- (void) addNewAudioTrack

{
    HBAudio *newAudio = [[HBAudio alloc] init];
    [newAudio setController: self];
    [self insertObject: newAudio inAudioArrayAtIndex: [self countOfAudioArray]];
    [newAudio setVideoContainerTag: [self videoContainerTag]];
    [newAudio setTrack: noneTrack];
    [newAudio setDrc: [NSNumber numberWithFloat: 0.0]];
    [newAudio setGain: [NSNumber numberWithFloat: 0.0]];
    [newAudio release];
}

#pragma mark -
#pragma mark Notification Handling

- (void) settingTrackToNone: (HBAudio *) newNoneTrack

{
    // If this is not the last track in the array we need to remove it.  We then need to see if a new
    // one needs to be added (in the case when we were at maximum count and this switching makes it
    // so we are no longer at maximum.
    NSUInteger index = [audioArray indexOfObject: newNoneTrack];

    if (NSNotFound != index && index < [self countOfAudioArray] - 1)
    {
        [self removeObjectFromAudioArrayAtIndex: index];
    }
    [self switchingTrackFromNone: nil]; // see if we need to add one to the list
}

- (void) switchingTrackFromNone: (HBAudio *) noLongerNoneTrack

{
    NSUInteger count = [self countOfAudioArray];
    BOOL needToAdd = NO;
    int maximumNumberOfAllowedAudioTracks = [HBController maximumNumberOfAllowedAudioTracks];

    // If there is no last track that is None and we are less than our maximum number of permitted tracks, we add one.
    if (count < maximumNumberOfAllowedAudioTracks)
    {
        if (0 < count)
        {
            HBAudio *lastAudio = [self objectInAudioArrayAtIndex: count - 1];
            if ([lastAudio enabled])
            {
                needToAdd = YES;
            }
        }
        else
        {
            needToAdd = YES;
        }
    }

    if (needToAdd)
    {
        [self addNewAudioTrack];
    }
}

// This gets called whenever the video container changes.
- (void) containerChanged: (NSNotification *) aNotification

{
    NSDictionary *notDict = [aNotification userInfo];

    [self setVideoContainerTag: [notDict objectForKey: keyContainerTag]];

    // Update each of the instances because this value influences possible settings.
    NSEnumerator *enumerator = [audioArray objectEnumerator];
    HBAudio *audioObject;

    while (nil != (audioObject = [enumerator nextObject]))
    {
        [audioObject setVideoContainerTag: [self videoContainerTag]];
    }

    /* Update the Auto Passthru Fallback Codec Popup */
    /* lets get the tag of the currently selected item first so we might reset it later */

    int selectedAutoPassthruFallbackEncoderTag = (int)[[fAudioFallbackPopUp selectedItem] tag];

    [fAudioFallbackPopUp removeAllItems];
    for (const hb_encoder_t *audio_encoder = hb_audio_encoder_get_next(NULL);
         audio_encoder != NULL;
         audio_encoder  = hb_audio_encoder_get_next(audio_encoder))
    {
        if ((audio_encoder->codec  & HB_ACODEC_PASS_FLAG) == 0 &&
            (audio_encoder->muxers & [[self videoContainerTag] integerValue]))
        {
            NSMenuItem *menuItem = [[fAudioFallbackPopUp menu] addItemWithTitle:[NSString stringWithUTF8String:audio_encoder->name]
                                                                         action:nil
                                                                  keyEquivalent:@""];
            [menuItem setTag:audio_encoder->codec];
        }
    }

    /* if we have a previously selected auto passthru fallback encoder tag, then try to select it */
    if (selectedAutoPassthruFallbackEncoderTag)
    {
        selectedAutoPassthruFallbackEncoderTag = [fAudioFallbackPopUp selectItemWithTag:selectedAutoPassthruFallbackEncoderTag];
    }
    /* if we had no previous fallback selected OR if selection failed
     * select the default fallback encoder (AC3) */
    if (!selectedAutoPassthruFallbackEncoderTag)
    {
        [fAudioFallbackPopUp selectItemWithTag:HB_ACODEC_AC3];
    }
}

- (void) titleChanged: (NSNotification *) aNotification

{
    NSDictionary *notDict = [aNotification userInfo];
    NSData *theData = [notDict objectForKey: keyTitleTag];
    hb_title_t *title = NULL;

    [theData getBytes: &title length: sizeof(title)];
    if (title)
    {
        hb_audio_config_t *audio;
        hb_list_t *list = title->list_audio;
        int i, count = hb_list_count(list);

        // Reinitialize the master list of available audio tracks from this title
        NSMutableArray *newTrackArray = [NSMutableArray array];
        [noneTrack release];
        noneTrack = [[NSDictionary dictionaryWithObjectsAndKeys:
                      [NSNumber numberWithInt: 0], keyAudioTrackIndex,
                      NSLocalizedString(@"None", @"None"), keyAudioTrackName,
                      [NSNumber numberWithInt: 0], keyAudioInputCodec,
                      nil] retain];
        [newTrackArray addObject: noneTrack];
        for (i = 0; i < count; i++)
        {
            audio = (hb_audio_config_t *) hb_list_audio_config_item(list, i);
            [newTrackArray addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       [NSNumber numberWithInt: i + 1], keyAudioTrackIndex,
                                       [NSString stringWithFormat: @"%d: %s", i, audio->lang.description], keyAudioTrackName,
                                       [NSNumber numberWithInt: audio->in.bitrate / 1000], keyAudioInputBitrate,
                                       [NSNumber numberWithInt: audio->in.samplerate], keyAudioInputSampleRate,
                                       [NSNumber numberWithInt: audio->in.codec], keyAudioInputCodec,
                                       [NSNumber numberWithInt: audio->in.codec_param], keyAudioInputCodecParam,
                                       [NSNumber numberWithUnsignedLongLong: audio->in.channel_layout], keyAudioInputChannelLayout,
                                       nil]];
        }
        self.masterTrackArray = newTrackArray;
    }
    else
    {
        self.masterTrackArray = nil;
    }

    // Reinitialize the configured list of audio tracks
    [self _clearAudioArray];

    if (![myController hasValidPresetSelected])
    {
        [self _ensureAtLeastOneNonEmptyTrackExists];
    }
}

#pragma mark -
#pragma mark KVC

- (NSUInteger) countOfAudioArray

{
    return [audioArray count];
}

- (HBAudio *) objectInAudioArrayAtIndex: (NSUInteger) index

{
    return [audioArray objectAtIndex: index];
}

- (void) insertObject: (HBAudio *) audioObject inAudioArrayAtIndex: (NSUInteger) index;

{
    [audioArray insertObject: audioObject atIndex: index];
}

- (void) removeObjectFromAudioArrayAtIndex: (NSUInteger) index

{
    [audioArray removeObjectAtIndex: index];
}

@end

