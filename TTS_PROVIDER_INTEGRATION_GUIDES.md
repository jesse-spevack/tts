# TTS Provider Integration Guides

This document provides step-by-step integration guides for three TTS providers: Google Cloud TTS, OpenAI TTS, and ElevenLabs TTS.

---

## 1. Google Cloud Text-to-Speech

### Overview
- **Pricing**: Pay-as-you-go, free tier available (1M characters/month for Standard voices)
- **Quality**: High quality, many voices and languages
- **Complexity**: Most complex setup (requires GCP account, service account, JSON credentials)

### Step-by-Step Integration

#### 1.1 Get API Credentials

1. **Create or select a Google Cloud project**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select an existing one
   - Note your project ID

2. **Enable billing for your project**
   - Navigate to Billing in the Cloud Console
   - Link a billing account (required even for free tier usage)

3. **Enable the Text-to-Speech API**
   - Go to "APIs & Services" > "Library"
   - Search for "Cloud Text-to-Speech API"
   - Click "Enable"

4. **Create a service account**
   - Go to "IAM & Admin" > "Service Accounts"
   - Click "Create Service Account"
   - Name it something like "tts-service-account"
   - Grant it the "Cloud Text-to-Speech User" role
   - Click "Done"

5. **Download the JSON key file**
   - Click on the service account you just created
   - Go to the "Keys" tab
   - Click "Add Key" > "Create new key"
   - Select "JSON" format
   - The JSON file will download automatically
   - **IMPORTANT**: Store this file securely, it contains sensitive credentials

#### 1.2 Store Credentials

Save the path to your JSON credentials file in your `.env`:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/path/to/your/credentials.json
```

#### 1.3 Add to Gemfile

```ruby
gem 'google-cloud-text_to_speech'
```

Then run: `bundle install`

#### 1.4 Authentication Scheme

Google Cloud uses **Service Account authentication** via JSON key files. The Ruby client library automatically looks for credentials in:
1. The path specified in `GOOGLE_APPLICATION_CREDENTIALS` environment variable
2. Application Default Credentials (ADC) if running on GCP infrastructure

#### 1.5 Simple cURL Example

```bash
# First, get an access token (requires gcloud CLI installed)
ACCESS_TOKEN=$(gcloud auth print-access-token)

# Create a request body file
cat > request.json << EOF
{
  "input": {
    "text": "Hello, this is a test of Google Cloud Text to Speech."
  },
  "voice": {
    "languageCode": "en-US",
    "name": "en-US-Standard-A",
    "ssmlGender": "FEMALE"
  },
  "audioConfig": {
    "audioEncoding": "MP3"
  }
}
EOF

# Make the API call
curl -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @request.json \
  "https://texttospeech.googleapis.com/v1/text:synthesize"

# Response contains base64-encoded audio in the "audioContent" field
# You'll need to decode it: echo "BASE64_STRING" | base64 --decode > output.mp3
```

#### 1.6 Ruby Implementation Snippet

```ruby
require "google/cloud/text_to_speech"

client = Google::Cloud::TextToSpeech.text_to_speech

# Configure the synthesis request
input = { text: "Hello, world!" }
voice = {
  language_code: "en-US",
  name: "en-US-Standard-A",
  ssml_gender: "FEMALE"
}
audio_config = { audio_encoding: "MP3" }

response = client.synthesize_speech(
  input: input,
  voice: voice,
  audio_config: audio_config
)

# The response's audio_content is binary data
File.open("output.mp3", "wb") do |file|
  file.write(response.audio_content)
end
```

---

## 2. OpenAI Text-to-Speech

### Overview
- **Pricing**: $15/1M characters (tts-1), $30/1M characters (tts-1-hd)
- **Quality**: Very good, 6 preset voices
- **Complexity**: Simple - just need an API key

### Step-by-Step Integration

#### 2.1 Get API Credentials

1. **Sign up for OpenAI account**
   - Go to [platform.openai.com](https://platform.openai.com/)
   - Create an account or sign in

2. **Generate an API key**
   - Navigate to API Keys section (User menu > "API keys")
   - Click "Create new secret key"
   - Give it a name (e.g., "TTS Project")
   - Copy the key immediately (starts with `sk-...`)
   - **IMPORTANT**: You won't be able to see it again

3. **Set up billing**
   - Add payment method in Billing section
   - You need credits to use the API

#### 2.2 Store Credentials

Save your API key in your `.env`:

```bash
OPENAI_API_KEY=sk-your-api-key-here
```

#### 2.3 Add to Gemfile

```ruby
gem 'ruby-openai'  # Official OpenAI Ruby client
# OR use net/http directly (no gem required)
```

Then run: `bundle install` (if using the gem)

#### 2.4 Authentication Scheme

OpenAI uses **Bearer Token authentication**. Every API request includes your API key in the `Authorization` header:

```
Authorization: Bearer YOUR_API_KEY
```

The API will return HTTP 401 if the key is missing or invalid.

#### 2.5 Simple cURL Example

```bash
curl https://api.openai.com/v1/audio/speech \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tts-1",
    "input": "Hello, this is a test of OpenAI text to speech.",
    "voice": "alloy",
    "response_format": "mp3"
  }' \
  --output hello.mp3
```

**Available voices**: alloy, echo, fable, onyx, nova, shimmer
**Available models**:
- `tts-1` - Fast, lower latency
- `tts-1-hd` - Higher quality audio

#### 2.6 Ruby Implementation Snippet (Using net/http)

```ruby
require 'net/http'
require 'json'
require 'uri'

def openai_tts(text, output_path, api_key)
  uri = URI('https://api.openai.com/v1/audio/speech')

  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{api_key}"
  request['Content-Type'] = 'application/json'
  request.body = {
    model: 'tts-1',
    input: text,
    voice: 'alloy',
    response_format: 'mp3'
  }.to_json

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  if response.code == '200'
    File.open(output_path, 'wb') { |file| file.write(response.body) }
    puts "Audio saved to #{output_path}"
  else
    raise "API Error: #{response.code} - #{response.body}"
  end
end

# Usage
openai_tts("Hello world!", "output.mp3", ENV['OPENAI_API_KEY'])
```

---

## 3. ElevenLabs Text-to-Speech

### Overview
- **Pricing**: Free tier (10k characters/month), paid plans start at $5/month
- **Quality**: Excellent, very natural-sounding voices
- **Complexity**: Simple - just need an API key

### Step-by-Step Integration

#### 3.1 Get API Credentials

1. **Sign up for ElevenLabs account**
   - Go to [elevenlabs.io](https://elevenlabs.io/)
   - Create a free account

2. **Get your API key**
   - Click on your profile icon
   - Go to "Profile" or "API Key" section
   - Copy your `xi-api-key`
   - **IMPORTANT**: Keep this key secure, don't expose in frontend code

3. **Choose a voice**
   - Browse available voices in the VoiceLab
   - Note the `voice_id` you want to use
   - Or fetch voice IDs via API: `https://api.elevenlabs.io/v1/voices`

#### 3.2 Store Credentials

Save your API key and preferred voice ID in your `.env`:

```bash
ELEVENLABS_API_KEY=your-api-key-here
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM  # Example voice ID
```

#### 3.3 Add to Gemfile

```ruby
gem 'elevenlabs'  # Community gem
# OR use net/http directly (no gem required)
```

Then run: `bundle install` (if using the gem)

#### 3.4 Authentication Scheme

ElevenLabs uses **API Key authentication** via the custom `xi-api-key` header:

```
xi-api-key: YOUR_API_KEY
```

No Bearer token prefix needed - just the raw API key.

#### 3.5 Simple cURL Example

```bash
# Using a specific voice ID
curl --request POST \
  --url https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM \
  --header 'Content-Type: application/json' \
  --header 'xi-api-key: YOUR_API_KEY' \
  --data '{
    "text": "Hello, this is a test of ElevenLabs text to speech.",
    "voice_settings": {
      "stability": 0.5,
      "similarity_boost": 0.8
    }
  }' \
  --output hello.mp3
```

**Get available voices**:
```bash
curl --request GET \
  --url https://api.elevenlabs.io/v1/voices \
  --header 'xi-api-key: YOUR_API_KEY'
```

#### 3.6 Ruby Implementation Snippet (Using net/http)

```ruby
require 'net/http'
require 'json'
require 'uri'

def elevenlabs_tts(text, output_path, api_key, voice_id)
  uri = URI("https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}")

  request = Net::HTTP::Post.new(uri)
  request['xi-api-key'] = api_key
  request['Content-Type'] = 'application/json'
  request.body = {
    text: text,
    voice_settings: {
      stability: 0.5,
      similarity_boost: 0.8
    }
  }.to_json

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  if response.code == '200'
    File.open(output_path, 'wb') { |file| file.write(response.body) }
    puts "Audio saved to #{output_path}"
  else
    raise "API Error: #{response.code} - #{response.body}"
  end
end

# Usage
elevenlabs_tts(
  "Hello world!",
  "output.mp3",
  ENV['ELEVENLABS_API_KEY'],
  ENV['ELEVENLABS_VOICE_ID']
)
```

---

## Comparison Summary

| Feature | Google Cloud | OpenAI | ElevenLabs |
|---------|-------------|--------|------------|
| **Setup Complexity** | High (GCP project, service account) | Low (API key only) | Low (API key only) |
| **Authentication** | Service Account JSON | Bearer token | Custom header (xi-api-key) |
| **Free Tier** | Yes (1M chars/month) | No | Yes (10k chars/month) |
| **Pricing** | $4-16 per 1M chars | $15-30 per 1M chars | $5-330/month plans |
| **Voice Quality** | Very good | Very good | Excellent (most natural) |
| **Voice Selection** | 220+ voices | 6 preset voices | Many natural voices |
| **Ruby Gem** | `google-cloud-text_to_speech` | `ruby-openai` or direct HTTP | `elevenlabs` or direct HTTP |

---

## Recommended Next Steps

1. **For MVP**: Start with **OpenAI** - simplest setup, good quality, predictable pricing
2. **For production**: Consider **Google Cloud** if you need the free tier or many language options
3. **For best quality**: Try **ElevenLabs** if voice naturalness is the top priority

All three providers return audio data that can be saved directly to MP3 files. Choose based on your budget, quality needs, and setup complexity tolerance.
