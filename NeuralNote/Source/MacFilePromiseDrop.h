//
// MacFilePromiseDrop.h — accept "promised" file drags on macOS.
//

#ifndef MacFilePromiseDrop_h
#define MacFilePromiseDrop_h

#include <JuceHeader.h>

/**
 * [ai] Apple Voice Memos, Bloom Memo and other modern macOS apps don't put a
 * file path on the drag pasteboard: they put a *file promise* and only write
 * the file once the destination asks for it. JUCE's native view ignores those
 * drags, so they show the "not allowed" cursor and nothing happens.
 *
 * install() patches the drag callbacks of the JUCE view hosting the editor so
 * promised files are received into a temp folder and then handed to the
 * regular FileDragAndDropTarget flow (fileDragEnter/filesDropped), exactly as
 * if a real file had been dropped. Drags that already carry file URLs are left
 * to JUCE untouched. On non-Apple platforms install() is a no-op.
 */
namespace MacFilePromiseDrop
{
void install(juce::Component& inEditor);
}

#endif // MacFilePromiseDrop_h
