//
// MacFilePromiseDrop.mm — see header for the why.
//

// [ai] Cocoa must come before JuceHeader.h: the generated header does
// `using namespace juce`, and Carbon's legacy Point/Component typedefs
// would otherwise become ambiguous inside the system headers.
#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <objc/runtime.h>
#endif
#endif

#include "MacFilePromiseDrop.h"

#if JUCE_MAC

#include <map>
#include <atomic>
#include <memory>

namespace
{
using DragOpIMP = NSDragOperation (*)(id, SEL, id<NSDraggingInfo>);
using VoidIMP = void (*)(id, SEL, id<NSDraggingInfo>);
using BoolIMP = BOOL (*)(id, SEL, id<NSDraggingInfo>);

struct OriginalIMPs {
    DragOpIMP draggingEntered = nullptr;
    DragOpIMP draggingUpdated = nullptr;
    VoidIMP draggingExited = nullptr;
    VoidIMP draggingEnded = nullptr;
    BoolIMP performDragOperation = nullptr;
};

juce::String toJuceString(NSString* string)
{
    return string != nil ? juce::String::fromUTF8([string UTF8String]) : juce::String();
}

NSString* toNSString(const juce::String& string)
{
    return [NSString stringWithUTF8String:string.toRawUTF8()];
}

OriginalIMPs gOriginal;
Class gPatchedClass = nil;
NSOperationQueue* gReceiveQueue = nil;

// [ai] Native view -> the JUCE editor living in it. A SafePointer so a closed
// editor simply reads back as null; entries are overwritten on re-install.
std::map<void*, juce::Component::SafePointer<juce::Component>> gEditorForView;

juce::ComponentPeer* peerForView(id view)
{
    auto it = gEditorForView.find((__bridge void*) view);

    if (it == gEditorForView.end() || it->second == nullptr)
        return nullptr;

    return it->second->getPeer();
}

NSArray<NSFilePromiseReceiver*>* promiseReceivers(NSPasteboard* pasteboard)
{
    NSArray* objects = [pasteboard readObjectsForClasses:@[[NSFilePromiseReceiver class]] options:@{}];
    return objects != nil ? objects : @[];
}

bool hasRealFileURLs(NSPasteboard* pasteboard)
{
    NSArray* urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                              options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    return urls != nil && urls.count > 0;
}

juce::String extensionForUTI(NSString* uti)
{
    if (uti == nil)
        return {};

    if (@available(macOS 11.0, *)) {
        UTType* type = [UTType typeWithIdentifier:uti];

        if (type != nil && type.preferredFilenameExtension != nil)
            return toJuceString(type.preferredFilenameExtension);
    }

    JUCE_BEGIN_IGNORE_DEPRECATION_WARNINGS
    if (CFStringRef ext = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef) uti, kUTTagClassFilenameExtension)) {
        auto result = juce::String::fromCFString(ext);
        CFRelease(ext);
        return result;
    }
    JUCE_END_IGNORE_DEPRECATION_WARNINGS

    return {};
}

// [ai] Before the file exists we still need to tell the UI what *kind* of file
// is hovering, so it can light up (or not) based on the extension. Prefer the
// promised file name, fall back to a placeholder carrying the promised type's
// extension.
juce::StringArray placeholderNames(NSArray<NSFilePromiseReceiver*>* receivers)
{
    juce::StringArray names;

    for (NSFilePromiseReceiver* receiver in receivers) {
        if (receiver.fileNames.count > 0) {
            for (NSString* name in receiver.fileNames)
                names.add(toJuceString(name));
            continue;
        }

        for (NSString* uti in receiver.fileTypes) {
            auto ext = extensionForUTI(uti);
            names.add(ext.isEmpty() ? juce::String("promised-file") : "promised-file." + ext);
        }
    }

    return names;
}

juce::Point<int> dropPosition(id view, id<NSDraggingInfo> sender, juce::ComponentPeer& peer)
{
    NSPoint viewPoint = [view convertPoint:[sender draggingLocation] fromView:nil];
    auto global = peer.localToGlobal(juce::Point<float>((float) viewPoint.x, (float) viewPoint.y));
    return peer.getComponent().getLocalPoint(nullptr, global).roundToInt();
}

juce::File makeDropFolder()
{
    auto folder = juce::File::getSpecialLocation(juce::File::tempDirectory)
                      .getChildFile("NeuralNote+ Dropped Files")
                      .getChildFile(juce::Uuid().toString());
    folder.createDirectory();
    return folder;
}

//==============================================================================
NSDragOperation swizzledDraggingMove(id self, SEL sel, id<NSDraggingInfo> sender)
{
    NSPasteboard* pasteboard = [sender draggingPasteboard];

    if (! hasRealFileURLs(pasteboard)) {
        NSArray<NSFilePromiseReceiver*>* receivers = promiseReceivers(pasteboard);

        if (receivers.count > 0) {
            if (auto* peer = peerForView(self)) {
                juce::ComponentPeer::DragInfo info;
                info.files = placeholderNames(receivers);
                info.position = dropPosition(self, sender, *peer);

                if (! peer->handleDragMove(info))
                    return NSDragOperationNone;

                // Pick an operation the source app allows, or the drop is refused.
                const auto allowed = [sender draggingSourceOperationMask];

                if (allowed & NSDragOperationCopy)
                    return NSDragOperationCopy;

                if (allowed & NSDragOperationGeneric)
                    return NSDragOperationGeneric;

                return allowed;
            }
        }
    }

    auto original = (sel == @selector(draggingEntered:)) ? gOriginal.draggingEntered : gOriginal.draggingUpdated;
    return original(self, sel, sender);
}

void swizzledDraggingExit(id self, SEL sel, id<NSDraggingInfo> sender)
{
    NSPasteboard* pasteboard = [sender draggingPasteboard];

    if (! hasRealFileURLs(pasteboard)) {
        NSArray<NSFilePromiseReceiver*>* receivers = promiseReceivers(pasteboard);

        if (receivers.count > 0) {
            if (auto* peer = peerForView(self)) {
                juce::ComponentPeer::DragInfo info;
                info.files = placeholderNames(receivers);
                info.position = dropPosition(self, sender, *peer);
                peer->handleDragExit(info);
            }

            return;
        }
    }

    auto original = (sel == @selector(draggingExited:)) ? gOriginal.draggingExited : gOriginal.draggingEnded;
    original(self, sel, sender);
}

BOOL swizzledPerformDragOperation(id self, SEL sel, id<NSDraggingInfo> sender)
{
    NSPasteboard* pasteboard = [sender draggingPasteboard];

    if (hasRealFileURLs(pasteboard))
        return gOriginal.performDragOperation(self, sel, sender);

    NSArray<NSFilePromiseReceiver*>* receivers = promiseReceivers(pasteboard);
    auto* peer = peerForView(self);

    if (receivers.count == 0 || peer == nullptr)
        return gOriginal.performDragOperation(self, sel, sender);

    // Refuse early if the UI wouldn't accept this kind of file anyway.
    juce::ComponentPeer::DragInfo info;
    info.files = placeholderNames(receivers);
    info.position = dropPosition(self, sender, *peer);

    if (! peer->handleDragMove(info)) {
        peer->handleDragExit(info);
        return NO;
    }

    auto editorIt = gEditorForView.find((__bridge void*) self);
    juce::Component::SafePointer<juce::Component> editor = editorIt != gEditorForView.end() ? editorIt->second : nullptr;
    const auto position = info.position;
    const auto folder = makeDropFolder();
    NSURL* destination = [NSURL fileURLWithPath:toNSString(folder.getFullPathName()) isDirectory:YES];

    // [ai] The source app writes the file asynchronously; NeuralNote only ever
    // loads files[0], so the first file that lands triggers the drop and the
    // rest are ignored. `fired` lives on the heap so every reader block sees
    // the same flag.
    auto fired = std::make_shared<std::atomic<bool>>(false);

    for (NSFilePromiseReceiver* receiver in receivers) {
        [receiver receivePromisedFilesAtDestination:destination
                                            options:@{}
                                     operationQueue:gReceiveQueue
                                             reader:^(NSURL* fileURL, NSError* error) {
                                                 if (error != nil || fileURL == nil) {
                                                     juce::Logger::writeToLog(
                                                         "File promise failed: "
                                                         + (error != nil ? toJuceString(error.localizedDescription)
                                                                         : juce::String("no file")));
                                                     return;
                                                 }

                                                 if (fired->exchange(true))
                                                     return;

                                                 juce::String path = toJuceString(fileURL.path);

                                                 juce::MessageManager::callAsync([editor, position, path]() {
                                                     if (editor == nullptr)
                                                         return;

                                                     if (auto* livePeer = editor->getPeer()) {
                                                         juce::ComponentPeer::DragInfo dropInfo;
                                                         dropInfo.files.add(path);
                                                         dropInfo.position = position;
                                                         livePeer->handleDragDrop(dropInfo);
                                                     }
                                                 });
                                             }];
    }

    return YES;
}

template <typename IMPType>
void swizzle(Class cls, SEL selector, IMPType replacement, IMPType& originalOut)
{
    Method method = class_getInstanceMethod(cls, selector);
    jassert(method != nullptr);

    if (method == nullptr)
        return;

    originalOut = reinterpret_cast<IMPType>(method_getImplementation(method));
    method_setImplementation(method, reinterpret_cast<IMP>(replacement));
}

void patchViewClassOnce(NSView* view)
{
    Class cls = [view class];

    if (gPatchedClass == cls)
        return;

    // [ai] JUCE creates exactly one dynamic view class per process, so a
    // second, different class here would mean JUCE changed its internals.
    jassert(gPatchedClass == nil);

    if (gPatchedClass != nil)
        return;

    gReceiveQueue = [[NSOperationQueue alloc] init];
    gReceiveQueue.name = @"NeuralNote+ file promise receiver";

    swizzle(cls, @selector(draggingEntered:), &swizzledDraggingMove, gOriginal.draggingEntered);
    swizzle(cls, @selector(draggingUpdated:), &swizzledDraggingMove, gOriginal.draggingUpdated);
    swizzle(cls, @selector(draggingExited:), &swizzledDraggingExit, gOriginal.draggingExited);
    swizzle(cls, @selector(draggingEnded:), &swizzledDraggingExit, gOriginal.draggingEnded);
    swizzle(cls, @selector(performDragOperation:), &swizzledPerformDragOperation, gOriginal.performDragOperation);

    gPatchedClass = cls;
}
} // namespace

namespace MacFilePromiseDrop
{
void install(juce::Component& inEditor)
{
    auto* peer = inEditor.getPeer();

    if (peer == nullptr)
        return;

    NSView* view = (__bridge NSView*) peer->getNativeHandle();

    if (view == nil)
        return;

    patchViewClassOnce(view);
    gEditorForView[(__bridge void*) view] = &inEditor;

    // Make sure every promise flavour reaches the view, on top of what JUCE registers.
    NSMutableArray* types = [NSMutableArray arrayWithArray:[view registeredDraggedTypes]];

    for (NSString* type in [NSFilePromiseReceiver readableDraggedTypes])
        if (! [types containsObject:type])
            [types addObject:type];

    [view registerForDraggedTypes:types];
}
} // namespace MacFilePromiseDrop

#else

namespace MacFilePromiseDrop
{
void install(juce::Component&) {}
} // namespace MacFilePromiseDrop

#endif
