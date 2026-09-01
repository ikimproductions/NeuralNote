//
// audio_file_test.h — AudioUtils::loadAudioFile on the formats added by the NeuralNote+ fork.
//

#ifndef NN_AUDIO_FILE_TEST_H
#define NN_AUDIO_FILE_TEST_H

#include <cmath>
#include <iostream>
#include <JuceHeader.h>
#include "AudioUtils.h"

namespace
{
// [ai] The fixtures are a 2 s mono 440 Hz sine at 48 kHz, 0.5 amplitude,
// encoded once with `afconvert` (AAC 64 kbps and Apple Lossless) — the two
// codecs Voice Memos and Bloom Memo write inside .m4a containers.
bool check_sine_m4a(const juce::File& file)
{
    juce::AudioBuffer<float> buffer;
    double sample_rate = 0.0;

    if (! AudioUtils::loadAudioFile(file, buffer, sample_rate)) {
        std::cout << "FAIL: could not load " << file.getFullPathName() << std::endl;
        return false;
    }

    if (std::abs(sample_rate - 48000.0) > 1e-6) {
        std::cout << "FAIL: sample rate " << sample_rate << " != 48000" << std::endl;
        return false;
    }

    if (buffer.getNumChannels() != 1) {
        std::cout << "FAIL: num channels " << buffer.getNumChannels() << " != 1" << std::endl;
        return false;
    }

    // Encoders add priming/padding frames: length must be ~2 s, not exact.
    const int expected_samples = 2 * 48000;
    if (std::abs(buffer.getNumSamples() - expected_samples) > 4096) {
        std::cout << "FAIL: num samples " << buffer.getNumSamples() << " far from " << expected_samples << std::endl;
        return false;
    }

    // RMS of a 0.5-amplitude sine is 0.5 / sqrt(2) ~= 0.354.
    const int start = 4800, count = 48000;
    const auto rms = buffer.getRMSLevel(0, start, count);
    if (std::abs(rms - 0.3536f) > 0.02f) {
        std::cout << "FAIL: rms " << rms << " far from 0.3536" << std::endl;
        return false;
    }

    // Peak must be near 0.5.
    const auto peak = buffer.getMagnitude(0, start, count);
    if (std::abs(peak - 0.5f) > 0.05f) {
        std::cout << "FAIL: peak " << peak << " far from 0.5" << std::endl;
        return false;
    }

    std::cout << "OK: " << file.getFileName() << " sr=" << sample_rate << " samples=" << buffer.getNumSamples()
              << " rms=" << rms << " peak=" << peak << std::endl;
    return true;
}
} // namespace

inline bool audio_file_test()
{
    bool ok = true;
    const juce::File data_dir(TEST_DATA_DIR);

    const auto extensions = AudioUtils::getSupportedAudioFileExtensions();
    std::cout << "Supported extensions: " << extensions.joinIntoString(", ") << std::endl;

#if JUCE_MAC || JUCE_WINDOWS
    if (! extensions.contains(".m4a")) {
        std::cout << "FAIL: .m4a not in supported extensions" << std::endl;
        ok = false;
    }

    ok &= check_sine_m4a(data_dir.getChildFile("sine_440_aac.m4a"));
    ok &= check_sine_m4a(data_dir.getChildFile("sine_440_alac.m4a"));
#endif

    // Extension matching must be case-insensitive (Finder happily shows "Memo.M4A").
    if (! AudioUtils::isAudioFileExtensionSupported("Recording.WAV")
        || ! AudioUtils::isAudioFileExtensionSupported("/tmp/x/New Recording 7.m4a")
        || AudioUtils::isAudioFileExtensionSupported("notes.txt")) {
        std::cout << "FAIL: isAudioFileExtensionSupported" << std::endl;
        ok = false;
    }

    // No duplicates / no dot-less entries in the user-facing list.
    for (const auto& ext: extensions) {
        if (! ext.startsWith(".") || extensions.indexOf(ext) != extensions.indexOf(ext, true)) {
            std::cout << "FAIL: bad extension entry '" << ext << "'" << std::endl;
            ok = false;
        }
    }

    // A bogus file must fail cleanly, not crash.
    juce::AudioBuffer<float> buffer;
    double sr = 0.0;
    if (AudioUtils::loadAudioFile(data_dir.getChildFile("notes.csv"), buffer, sr)) {
        std::cout << "FAIL: loading a csv reported success" << std::endl;
        ok = false;
    }

    return ok;
}

#endif // NN_AUDIO_FILE_TEST_H
