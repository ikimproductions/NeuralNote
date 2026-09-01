//
// Created by Damien Ronssin on 09.03.23.
//

#include "AudioUtils.h"

#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"
#include "minimp3_ex.h"

namespace AudioUtils
{
bool loadAudioFile(const juce::File& inFile, AudioBuffer<float>& outBuffer, double& outSampleRate)
{
    if (inFile.getFileExtension().equalsIgnoreCase(".mp3")) {
        return _loadMP3File(inFile.getFullPathName().toStdString(), outBuffer, outSampleRate);
    }

    // Register different audio formats
    auto audio_format_manager = createAudioFormatManager();

    std::unique_ptr<juce::AudioFormatReader> format_reader;
    format_reader.reset(audio_format_manager->createReaderFor(inFile));

    // Verify format reader is not null
    if (!format_reader)
        return false;

    // Get properties of input audio
    outSampleRate = format_reader->sampleRate;
    int num_source_samples = static_cast<int>(format_reader->lengthInSamples);
    int num_channels = (int) format_reader->numChannels;

    outBuffer.setSize(num_channels, num_source_samples);

    // Read source file. If not successful, return false
    if (!format_reader->read(&outBuffer, 0, num_source_samples, 0, true, true))
        return false;

    return true;
}

StringArray getSupportedAudioFileExtensions()
{
    StringArray supported_extensions;
    supported_extensions.add(".mp3");

    auto audio_format_manager = createAudioFormatManager();
    for (auto& format: *audio_format_manager) {
        // [ai] The OS decoders advertise everything they can demux (.mov, .qt,
        // .mpeg, ...). Only the audio containers people actually drop are
        // listed for them, so the file picker and error text stay readable.
        const bool is_os_decoder =
#if JUCE_MAC || JUCE_IOS
            dynamic_cast<juce::CoreAudioFormat*>(format) != nullptr;
#elif JUCE_WINDOWS
            dynamic_cast<juce::WindowsMediaAudioFormat*>(format) != nullptr;
#else
            false;
#endif
        if (is_os_decoder)
            continue;

        for (auto& extension: format->getFileExtensions()) {
            auto normalised = extension.startsWith(".") ? extension.toLowerCase() : "." + extension.toLowerCase();
            supported_extensions.addIfNotAlreadyThere(normalised);
        }
    }

#if JUCE_MAC || JUCE_IOS
    supported_extensions.addArray({".m4a", ".m4b", ".m4r", ".aac", ".mp4", ".caf", ".aifc"});
#elif JUCE_WINDOWS
    supported_extensions.addArray({".m4a", ".aac", ".mp4", ".wma"});
#endif

    return supported_extensions;
}

bool isAudioFileExtensionSupported(const String& inFilename)
{
    static const StringArray supported_extensions = getSupportedAudioFileExtensions();

    return std::any_of(supported_extensions.begin(), supported_extensions.end(), [&inFilename](const String& ext) {
        return inFilename.endsWithIgnoreCase(ext);
    });
}

String getFileChooserWildcardPattern()
{
    StringArray patterns;

    for (const auto& ext: getSupportedAudioFileExtensions()) {
        patterns.add("*" + ext);
    }

    return patterns.joinIntoString(";");
}

std::unique_ptr<AudioFormatManager> createAudioFormatManager()
{
    auto audio_format_manager = std::make_unique<AudioFormatManager>();
    audio_format_manager->registerFormat(new juce::WavAudioFormat, true);
    audio_format_manager->registerFormat(new juce::AiffAudioFormat, false);
    audio_format_manager->registerFormat(new juce::FlacAudioFormat, false);
    audio_format_manager->registerFormat(new juce::OggVorbisAudioFormat, false);

#if JUCE_MAC || JUCE_IOS
    // [ai] Apple's own decoder: adds .m4a/.aac/.mp4/.caf (Voice Memos and
    // Bloom Memo record AAC or ALAC inside .m4a). Registered last so the
    // dedicated JUCE codecs above keep handling the formats they own.
    audio_format_manager->registerFormat(new juce::CoreAudioFormat, false);
#elif JUCE_WINDOWS
    audio_format_manager->registerFormat(new juce::WindowsMediaAudioFormat, false);
#endif

    return std::move(audio_format_manager);
}

void resampleBuffer(const AudioBuffer<float>& inBuffer,
                    AudioBuffer<float>& outBuffer,
                    double inSourceSampleRate,
                    double inTargetSampleRate)
{
    if (inSourceSampleRate == inTargetSampleRate) {
        outBuffer.makeCopyOf(inBuffer);
        return;
    }

    Resampler resampler;
    // Prepare resampler
    resampler.prepareToPlay(inSourceSampleRate, inBuffer.getNumSamples(), inTargetSampleRate);
    auto num_expected_samples_after_resample = resampler.getNumOutSamplesOnNextProcessBlock(inBuffer.getNumSamples());

    outBuffer.setSize(inBuffer.getNumChannels(), num_expected_samples_after_resample);

    for (int ch = 0; ch < inBuffer.getNumChannels(); ch++) {
        resampler.reset();
        int num_samples_after_resample = resampler.processBlock(
            inBuffer.getReadPointer(ch), outBuffer.getWritePointer(ch), inBuffer.getNumSamples());
        jassertquiet(num_samples_after_resample == num_expected_samples_after_resample);
    }
}

bool _loadMP3File(const std::string& filename, juce::AudioBuffer<float>& outBuffer, double& outSampleRate)
{
    mp3dec_t mp3d;
    mp3dec_file_info_t info;
    int loadResult = mp3dec_load(&mp3d, filename.c_str(), &info, nullptr, nullptr);

    if (loadResult) {
        return false;
    }

    outBuffer.setSize(info.channels, static_cast<int>(info.samples / info.channels));

    for (size_t i = 0; i < info.samples; ++i) {
        size_t channel = i % info.channels;
        outBuffer.setSample((int) channel, static_cast<int>(i / info.channels), (float) info.buffer[i] / 32768.0f);
    }

    outSampleRate = static_cast<double>(info.hz);
    free(info.buffer);
    return true;
}

} // namespace AudioUtils