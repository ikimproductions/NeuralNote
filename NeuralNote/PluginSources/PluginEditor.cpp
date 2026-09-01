#include "PluginProcessor.h"
#include "PluginEditor.h"
#include "MacFilePromiseDrop.h"

NeuralNoteEditor::NeuralNoteEditor(NeuralNoteAudioProcessor& p)
    : AudioProcessorEditor(&p)
{
    mMainView = std::make_unique<NeuralNoteMainView>(p);

    addAndMakeVisible(*mMainView);
    setSize(1000, 640);

    getLookAndFeel().setDefaultSansSerifTypeface(UIDefines::MONTSERRAT_REGULAR());

    mMainView->setLookAndFeel(&mNeuralNoteLnF);
}

NeuralNoteEditor::~NeuralNoteEditor()
{
    mMainView->setLookAndFeel(nullptr);
}

void NeuralNoteEditor::paint(juce::Graphics& g)
{
}

void NeuralNoteEditor::resized()
{
    mMainView->setBounds(getLocalBounds());
}

void NeuralNoteEditor::parentHierarchyChanged()
{
    // [ai] Called once the editor sits inside a native window (standalone or
    // host). That is the earliest moment the native view exists, which the
    // macOS file-promise drop support needs to hook into.
    MacFilePromiseDrop::install(*this);
}
