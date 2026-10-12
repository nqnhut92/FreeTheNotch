// Loaded by /usr/bin/perl (see media-bridge.pl), same idea as Atoll's
// mediaremote-adapter: the perl process is allowed to read Now Playing,
// this app's process is not (macOS 15.4+).
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetStateFn)(dispatch_queue_t, void (^)(int));
typedef void (*SendFn)(unsigned int, const void *);
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*SetModeFn)(int);
typedef void (*RegisterFn)(dispatch_queue_t);

static GetInfoFn getInfo;
static GetStateFn getState;
static SendFn sendCommand;
static GetPIDFn getPID;
// Atoll's NowPlayingController: MRMediaRemoteSetShuffleMode / SetRepeatMode.
// Shuffle: 1 off, 3 tracks. Repeat: 1 off, 2 one, 3 all.
static SetModeFn setShuffleMode;
static SetModeFn setRepeatMode;
static dispatch_queue_t emitQueue;
static pthread_mutex_t emitLock = PTHREAD_MUTEX_INITIALIZER;
static char lastArtSig[24];
static char lastTitle[512];

static void json_escape(const char *in, char *out, size_t cap) {
    size_t j = 0;
    if (!in) in = "";
    for (size_t i = 0; in[i] && j + 6 < cap; i++) {
        unsigned char c = (unsigned char)in[i];
        if (c == '"' || c == '\\') {
            out[j++] = '\\';
            out[j++] = (char)c;
        } else if (c == '\n') {
            out[j++] = '\\';
            out[j++] = 'n';
        } else if (c < 0x20) {
            continue;
        } else {
            out[j++] = (char)c;
        }
    }
    out[j] = 0;
}

static int cf_string(CFDictionaryRef info, CFStringRef key, char *buf, size_t cap) {
    CFStringRef value = CFDictionaryGetValue(info, key);
    if (!value || CFGetTypeID(value) != CFStringGetTypeID()) {
        buf[0] = 0;
        return 0;
    }
    return CFStringGetCString(value, buf, cap, kCFStringEncodingUTF8) ? 1 : 0;
}

static double cf_number(CFDictionaryRef info, CFStringRef key) {
    CFNumberRef value = CFDictionaryGetValue(info, key);
    double n = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue(value, kCFNumberDoubleType, &n);
    }
    return n;
}

static char *base64(const unsigned char *data, size_t len) {
    static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t outLen = 4 * ((len + 2) / 3);
    char *out = malloc(outLen + 1);
    if (!out) return NULL;
    size_t j = 0;
    for (size_t i = 0; i < len; i += 3) {
        unsigned int n = (unsigned int)data[i] << 16;
        if (i + 1 < len) n |= (unsigned int)data[i + 1] << 8;
        if (i + 2 < len) n |= (unsigned int)data[i + 2];
        out[j++] = table[(n >> 18) & 63];
        out[j++] = table[(n >> 12) & 63];
        out[j++] = (i + 1 < len) ? table[(n >> 6) & 63] : '=';
        out[j++] = (i + 2 < len) ? table[n & 63] : '=';
    }
    out[j] = 0;
    return out;
}

static void emit(void) {
    if (!getInfo) return;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block int state = -1;
    __block CFDictionaryRef info = NULL;
    if (getState) {
        getState(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(int s) {
            state = s;
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }
    getInfo(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(CFDictionaryRef value) {
        if (value) CFRetain(value);
        info = value;
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));

    // Get the PID (Atoll's approach: PID -> bundle ID via NSRunningApplication).
    __block int appPID = -1;
    if (getPID) {
        getPID(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(int pid) {
            appPID = pid;
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    }

    pthread_mutex_lock(&emitLock);
    if (!info) {
        printf("{\"playing\":false}\n");
        fflush(stdout);
        pthread_mutex_unlock(&emitLock);
        return;
    }

    char title[512], artist[512], titleJSON[1024], artistJSON[1024];
    char bundleID[256], bundleJSON[512];
    cf_string(info, CFSTR("kMRMediaRemoteNowPlayingInfoTitle"), title, sizeof title);
    cf_string(info, CFSTR("kMRMediaRemoteNowPlayingInfoArtist"), artist, sizeof artist);
    // Bundle ID is resolved from PID in Swift (Atoll's approach).
    // Keep the info-dict fallback for completeness.
    bundleID[0] = 0;
    if (!cf_string(info, CFSTR("kMRMediaRemoteNowPlayingApplicationBundleIdentifier"), bundleID, sizeof bundleID)) {
        cf_string(info, CFSTR("kMRMediaRemoteNowPlayingInfoApplicationBundleIdentifier"), bundleID, sizeof bundleID);
    }
    json_escape(title, titleJSON, sizeof titleJSON);
    json_escape(artist, artistJSON, sizeof artistJSON);
    json_escape(bundleID, bundleJSON, sizeof bundleJSON);
    double rate = cf_number(info, CFSTR("kMRMediaRemoteNowPlayingInfoPlaybackRate"));
    double duration = cf_number(info, CFSTR("kMRMediaRemoteNowPlayingInfoDuration"));
    double elapsed = cf_number(info, CFSTR("kMRMediaRemoteNowPlayingInfoElapsedTime"));
    int playing = (state == 1) || (rate > 0.01);
    // 0 = the app did not publish the key.
    int shuffleMode = (int)cf_number(info, CFSTR("kMRMediaRemoteNowPlayingInfoShuffleMode"));
    int repeatMode = (int)cf_number(info, CFSTR("kMRMediaRemoteNowPlayingInfoRepeatMode"));

    // New track: forget the artwork signature so its art is sent even when
    // it matches the previous track's (same album). Swift clears the old
    // art on a track change, like Atoll.
    if (strcmp(title, lastTitle) != 0) {
        strncpy(lastTitle, title, sizeof lastTitle);
        lastTitle[sizeof lastTitle - 1] = 0;
        lastArtSig[0] = 0;
    }

    char *art = NULL;
    CFDataRef blob = CFDictionaryGetValue(info, CFSTR("kMRMediaRemoteNowPlayingInfoArtworkData"));
    if (blob && CFGetTypeID(blob) == CFDataGetTypeID()) {
        const unsigned char *bytes = CFDataGetBytePtr(blob);
        CFIndex len = CFDataGetLength(blob);
        char sig[24];
        snprintf(sig, sizeof sig, "%ld:%02x%02x%02x%02x", (long)len,
                 len > 0 ? bytes[0] : 0, len > 1 ? bytes[1] : 0,
                 len > 2 ? bytes[2] : 0, len > 3 ? bytes[3] : 0);
        if (strcmp(sig, lastArtSig) != 0) {
            strncpy(lastArtSig, sig, sizeof lastArtSig);
            lastArtSig[sizeof lastArtSig - 1] = 0;
            art = base64(bytes, (size_t)len);
        }
    }

    if (art) {
        printf("{\"playing\":%s,\"title\":\"%s\",\"artist\":\"%s\",\"duration\":%.3f,\"elapsed\":%.3f,\"artwork\":\"%s\",\"bundleIdentifier\":\"%s\",\"pid\":%d,\"shuffleMode\":%d,\"repeatMode\":%d}\n",
               playing ? "true" : "false", titleJSON, artistJSON, duration, elapsed, art, bundleJSON, appPID, shuffleMode, repeatMode);
        free(art);
    } else {
        printf("{\"playing\":%s,\"title\":\"%s\",\"artist\":\"%s\",\"duration\":%.3f,\"elapsed\":%.3f,\"bundleIdentifier\":\"%s\",\"pid\":%d,\"shuffleMode\":%d,\"repeatMode\":%d}\n",
               playing ? "true" : "false", titleJSON, artistJSON, duration, elapsed, bundleJSON, appPID, shuffleMode, repeatMode);
    }
    fflush(stdout);
    CFRelease(info);
    pthread_mutex_unlock(&emitLock);
}

static void note(CFNotificationCenterRef center, void *observer, CFNotificationName name,
                 const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(emitQueue, ^{ emit(); });
}

static void *stdin_thread(void *unused) {
    (void)unused;
    char buf[64];
    while (fgets(buf, sizeof buf, stdin)) {
        unsigned int command = 0;
        if (strncmp(buf, "toggle", 6) == 0) command = 2;
        else if (strncmp(buf, "next", 4) == 0) command = 4;
        else if (strncmp(buf, "prev", 4) == 0) command = 5;
        else if (strncmp(buf, "shuffle ", 8) == 0) {
            if (setShuffleMode) setShuffleMode(atoi(buf + 8));
        } else if (strncmp(buf, "repeat ", 7) == 0) {
            if (setRepeatMode) setRepeatMode(atoi(buf + 7));
        }
        if (command && sendCommand) sendCommand(command, NULL);
        dispatch_async(emitQueue, ^{ emit(); });
    }
    return NULL;
}

__attribute__((constructor))
static void start(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "MediaBridge: %s\n", dlerror());
        return;
    }
    getInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    getState = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState");
    sendCommand = dlsym(handle, "MRMediaRemoteSendCommand");
    // Atoll's approach: PID -> bundle ID via NSRunningApplication (in Swift).
    getPID = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID");
    setShuffleMode = dlsym(handle, "MRMediaRemoteSetShuffleMode");
    setRepeatMode = dlsym(handle, "MRMediaRemoteSetRepeatMode");
    emitQueue = dispatch_queue_create("ftn.media.emit", DISPATCH_QUEUE_SERIAL);

    // Atoll's mediaremote-adapter: MediaRemote only posts its change
    // notifications (on the LOCAL center, not Darwin) after this call.
    // Before, we listened on the Darwin center, never heard anything, and
    // only the 1s timer picked up a new track / app / artwork.
    RegisterFn registerFn = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (registerFn) registerFn(emitQueue);
    CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
    CFStringRef names[] = {
        CFSTR("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
        CFSTR("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
        CFSTR("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
    };
    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
        CFNotificationCenterAddObserver(center, NULL, note, names[i], NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, emitQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(timer, ^{ emit(); });
    dispatch_resume(timer);

    pthread_t thread;
    pthread_create(&thread, NULL, stdin_thread, NULL);
    pthread_detach(thread);
}
