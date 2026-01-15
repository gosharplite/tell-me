<!--
Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
SPDX-License-Identifier: MIT
-->
<p align="center">
  <img src="assets/tell-me.png" alt="tell-me logo" width="250">
</p>

# tell-me: A Bash Gemini CLI Assistant

A lightweight, terminal-based interface for Google's Gemini API. The `tell-me` tool allows you to chat with Gemini models directly from your shell, maintaining conversation history in local JSON files and rendering responses with Markdown formatting.

## 🚀 Features

*   **Run From Anywhere**: Set up a global alias to call the assistant from any directory on your system.
*   **Context-Aware**: Maintains conversation history automatically in a centralized JSON file.
*   **System Prompts**: Customizable persona and instructions via YAML configuration.
*   **Rich Output**: Renders Markdown responses using `glow` (with graceful fallback to ANSI colors).
*   **Smart Auth**: Uses `gcloud` for authentication with intelligent token caching to minimize latency.
*   **Sandboxed Environment**: Spawns a dedicated sub-shell with custom aliases (`a`, `aa`, `recap`, `dump`, `h`).
*   **Continuous Workflow**: Navigate your filesystem with `cd` and analyze multiple projects back-to-back within a single, persistent chat session.
*   **Developer Friendly**: Includes `dump.sh` to bundle any project's code (respecting `.gitignore`) for LLM analysis.
*   **Usage Metrics**: Logs API token usage (Hit/Miss/New) and costs in a sidecar `.log` file.

## ⚠️ Important Disclaimers

### Security & Privacy
This tool sends the content of your prompts and any files bundled with `dump` to the Google Gemini API. **Do not send sensitive information, proprietary code, or any files containing secrets** like API keys, passwords, or personal data. By using this tool, you are responsible for the data you transmit.

### API Costs
Using the Google Gemini API is subject to `Google Cloud's pricing model`. While the tool includes a logger to track token usage, you are responsible for any costs incurred on your Google Cloud account. Please monitor your usage and set up billing alerts in your Google Cloud project.

## 📋 Prerequisites

Ensure the following tools are installed and available in your `$PATH`:

*   **Bash** (4.0+)
*   **Google Cloud SDK** (`gcloud`) - *Required for authentication*
*   **jq** - *JSON processing*
*   **yq** - *YAML processing*
    *   **Important**: This project requires the **Go implementation** ([mikefarah/yq](https://github.com/mikefarah/yq)).
    *   *Do not use the Python wrapper (`pip install yq`), as the syntax is incompatible.*
*   **curl** - *API requests*
*   **glow** - *(Optional) For beautiful Markdown rendering.*
*   **fzf** - *(Optional) Required for the `h` (hack) menu.*
*   **git** - *(Optional) Improves `dump.sh` by accurately listing files based on `.gitignore` rules.*
*   **tree** - *(Optional) Provides a visual directory tree in the `dump.sh` output.*

### Initial Setup
Authenticate with Google Cloud:
```bash
gcloud auth login
gcloud auth application-default set-quota-project <YOUR_PROJECT_ID>
```

## 🛠️ Installation & Setup

1.  **Clone the repository**:
    ```bash
    git clone git@github.com:gosharplite/tell-me.git /path/to/your/clone
    cd /path/to/your/clone
    ```

2.  **Make scripts executable**:
    This command ensures all necessary scripts in the project are runnable.
    ```bash
    chmod +x a aa *.sh
    ```

3.  **(Recommended) Create a Global Alias**
    To run the assistant from any directory, add the following to your shell configuration file (e.g., `~/.bashrc` or `~/.zshrc`). This makes the tool much more convenient to use.

    **Remember to replace `/path/to/your/clone` with the actual path to the directory from step 1.**

    ```bash
    # Add to ~/.bashrc or ~/.zshrc

    # Define a home directory for the tell-me CLI Assistant
    export AIT_HOME="/path/to/your/clone"

    # Create a convenient alias to start a new session
    alias ait='$AIT_HOME/tell-me.sh $AIT_HOME/yaml/gemini.yaml new'
    ```
    After saving the file, reload your shell configuration with `source ~/.bashrc` or `source ~/.zshrc`.

## ⚙️ Configuration

You can customize the AI's persona, model, and session identifier by editing `yaml/gemini.yaml`.

The `MODE` key is particularly important as it acts as a unique name for a chat session. Its value is used to automatically generate the names for the history file (e.g., `last-assist-gemini.json`) and any project dumps within the `output` directory. This allows you to maintain separate configurations and conversation histories for different tasks (e.g., one for coding, another for general assistance).

A typical configuration looks like this:
```yaml
MODE: "assist-gemini"
PERSON: "You are a helpful AI..."
AIMODEL: "gemini-pro-latest"
AIURL: "https://generativelanguage.googleapis.com/v1beta/models"
```
The tool is pre-configured to work out-of-the-box with the global alias setup, automatically storing all session files in the `output` directory within your cloned project folder.

## 💻 Usage

### 1. Start a Session
If you've set up the alias, simply type `ait` in your terminal from any directory.

```bash
ait
```
This will start a new, clean chat session.

To send a message immediately upon starting, you can do:
```bash
ait "What is the capital of Mongolia?"
```
For non-interactive use (send a prompt and exit), use the `nobash` argument:
```bash
ait nobash "Translate 'hello world' to French"
```

### 2. Interactive Commands
Once inside the session (prompt: `user@tell-me:gemini$`), use these aliases:

*   **`a "Your message"`**: Sends a single-line message.
*   **`aa`**: Starts **Multi-line Input Mode**. Type or paste text, then press `Ctrl+D` to send.
*   **`recap`**: Re-renders the full chat history.
    *   `recap -l`: Show only the last response.
    *   `recap -c`: Extract content from the last response. **Note**: For clean output, instruct the AI to provide "code only" first.
    *   `recap -r`: Force raw output (displays raw Markdown and ANSI colors instead of rendering with `glow`).
    *   `recap -l -r`: Combine flags (e.g., show only the last response in raw format).
*   **`dump [dir]`**: Bundles the source code of a project (defaults to the current directory).
*   **`h`**: Opens an `fzf`-powered menu with shortcuts like:
    *   `analyze-project`: Bundles the current project with `dump` and asks for a general analysis.
    *   `code-review`: Asks the AI to perform a code review.
    *   `ext-dependency`: Asks the AI to list external dependencies and their auth methods.
    *   `code-only`: Prompts the AI to provide only code in its next response.
    *   ... and more.

### Example: Analyzing Multiple Projects in One Session
The true power of the global alias is analyzing projects on the fly. Because `ait` starts an interactive sub-shell, you can navigate your filesystem and analyze multiple projects without restarting.

```bash
# 1. Go to the first project directory
cd ~/dev/project-alpha

# 2. Start the AI assistant
ait
# You are now inside the tell-me sub-shell.

# 3. Analyze the first project
# The '.' refers to your current directory (~/dev/project-alpha).
# Use the interactive helper for a common task:
user@tell-me:gemini$ h  # --> select "analyze-project" from the menu

# The AI responds with its analysis of project-alpha.

# 4. Navigate to a second project *within the same session*
user@tell-me:gemini$ cd ../project-beta

# 5. Analyze the second project, asking for a comparison
# Now, '.' refers to ~/dev/project-beta.
# ⚠️ WARNING: Piping sends the data immediately. Check the dump size first!
# Run 'dump' alone to see the token estimate if you are unsure about costs.
user@tell-me:gemini$ dump . | a "Now, analyze this second project and compare its architecture to the first one."

# The AI now has the context of both projects and can perform a comparison.
```

### 4. Exit
Type `exit` or press `Ctrl+D` to leave the chat session.

## 📝 Notes

*   **Token Caching**: Access tokens are cached in a temporary directory (`$TMPDIR` or `/tmp`) to speed up sequential requests.
*   **Backups**: Every response triggers a versioned backup of the history file.
*   **Metrics**: Token usage is logged in `<filename>.log` alongside the JSON history.

## 📜 License
[MIT](LICENSE)
