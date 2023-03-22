// Various helper functions and utilities

#pragma once

#include <string>
#include <map>
#include <vector>
#include <random>
#include <thread>

//
// CLI argument parsing
//

struct gpt_params {
    int32_t seed      = -1; // RNG seed
    int32_t n_threads = std::min(4, (int32_t) std::thread::hardware_concurrency());
    int32_t n_predict = 128; // new tokens to predict
    int32_t repeat_last_n = 64;  // last n tokens to penalize
    int32_t n_ctx = 512; //context size
    bool memory_f16 = false; // use f16 instead of f32 for memory kv

    // sampling parameters
    int32_t top_k = 40;
    float   top_p = 0.95f;
    float   temp  = 0.80f;
    float   repeat_penalty  = 1.30f;

    int32_t n_batch = 8; // batch size for prompt processing

    std::string model      = "";
    std::string prompt     = "";

    bool random_prompt = false;

    bool use_color = false; // use color to distinguish generations and inputs

    bool interactive = false; // interactive mode
    bool interactive_start = false; // reverse prompt immediately
    std::vector<std::string> antiprompt; // string upon seeing which more user input is prompted
    bool instruct    = false; // instruction mode (used for Alpaca models)
    bool ignore_eos = false; // do not stop generating after eos
};

bool gpt_params_parse(int argc, char ** argv, gpt_params & params);

void gpt_print_usage(int argc, char ** argv, const gpt_params & params);

std::string gpt_random_prompt(std::mt19937 & rng);

//
// Model file parsing
//

#define FILE_MAGIC_UNVERSIONED 0x67676d6c // pre-versioned files
#define FILE_MAGIC 0x67676d66 // 'ggmf' in hex
#define FILE_VERSION 1

//
// Vocab utils
//

struct gpt_vocab {
    using id    = int32_t;
    using token = std::string;

    std::map<token, id> token_to_id;
    std::map<id, token> id_to_token;
    std::map<id, float> score;
};

void replace(std::string & str, const std::string & needle, const std::string & replacement);

// poor-man's JSON parsing
std::map<std::string, int32_t> json_parse(const std::string & fname);

// split text into tokens
//
// ref: https://github.com/openai/gpt-2/blob/a74da5d99abaaba920de8131d64da2862a8f213b/src/encoder.py#L53
//
// Regex (Python):
// r"""'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"""
//
// Regex (C++):
// R"('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^\s[:alpha:][:digit:]]+|\s+(?!\S)|\s+)"
//
std::vector<gpt_vocab::id> gpt_tokenize(const gpt_vocab & vocab, const std::string & text);

// TODO: this is probably wrong, but I cannot figure out how this tokenizer works ..
// ref: https://github.com/google/sentencepiece
std::vector<gpt_vocab::id> llama_tokenize(const gpt_vocab & vocab, std::string_view text, bool bos);

// load the tokens from encoder.json
bool gpt_vocab_init(const std::string & fname, gpt_vocab & vocab);

// sample next token given probabilities for each embedding
//
//   - consider only the top K tokens
//   - from them, consider only the top tokens with cumulative probability > P
//
gpt_vocab::id llama_sample_top_p_top_k(
        const gpt_vocab & vocab,
        const float * logits,
        std::vector<gpt_vocab::id> & last_n_tokens,
        double repeat_penalty,
        int top_k,
        double top_p,
        double temp,
        std::mt19937 & rng);

// filer to top K tokens from list of logits
void sample_top_k(std::vector<std::pair<double, gpt_vocab::id>> & logits_id, int top_k);

//
// Quantization
//

size_t ggml_quantize_q4_0(float * src, void * dst, int n, int k, int qk, int64_t * hist);
size_t ggml_quantize_q4_1(float * src, void * dst, int n, int k, int qk, int64_t * hist);
