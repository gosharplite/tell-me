<!--
Copyright (c) 2026 Tony Hsu <gosharplite@gmail.com>
SPDX-License-Identifier: MIT
-->

# tell-me: A Bash Gemini CLI Assistant

A lightweight, terminal-based interface for Google's Gemini API. The `tell-me` tool allows you to chat with Gemini models directly from your shell, maintaining conversation history in local JSON files and rendering responses with Markdown formatting.

## 🚀 Features

*   **Run From Anywhere**: Set up a global alias to call the assistant from any directory on your system.
*   **Context-Aware**: Maintains conversation history automatically in a centralized JSON file.
*   **System Prompts**: Customizable persona and instructions via YAML configuration.
*   **Rich Output**: Renders Markdown responses using `glow` (with graceful fallback to ANSI colors).
*   **Smart Auth**: Uses `gcloud` for authentication with intelligent token caching to minimize latency.
*   **Sandboxed Environment**: Spawns a dedicated sub-shell with custom aliases (`a`, `aa`, `recap`, `dump`, `h`).
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
*   **glow** - *(Optional) For beautiful Markdown rendering*
*   **fzf** - *(Optional) Required for the `h` (hack) menu*

### Initial Setup
Authenticate with Google Cloud:
```bash
gcloud auth login
gcloud auth application-default set-quota-project <YOUR_PROJECT_ID>
```

## 🛠️ Installation & Setup

1.  **Clone the repository**:
    ```bash
    git clone <repository_url> /path/to/your/clone
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

You can customize the AI's persona, model, and other settings by editing `yaml/gemini.yaml`. The tool is pre-configured to work out-of-the-box with the global alias setup, automatically storing session files in the `output` directory within your cloned project folder.

A typical configuration looks like this:
```yaml
MODE: "assist-gnative"
file: "./output/history.json" # This path is automatically handled
PERSON: "You are a helpful AI..."
AIMODEL: "gemini-pro-latest"
AIURL: "https://generativelanguage.googleapis.com/v1beta/models"
```

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
    *   `recap -c`: Extract code blocks from the last response.
*   **`dump [dir]`**: Bundles the source code of a project (defaults to the current directory).
*   **`h`**: Opens an `fzf`-powered menu with shortcuts like:
    *   `analyze-project`: Bundles the current project with `dump` and asks for a general analysis.
    *   `code-review`: Asks the AI to perform a code review.
    *   `ext-dependency`: Asks the AI to list external dependencies and their auth methods.
    *   `code-only`: Prompts the AI to provide only code in its next response.
    *   ... and more.

### Example: Analyzing Another Project
The true power of the global alias is analyzing other projects on the fly.

```bash
# 1. Go to any project directory
cd ~/dev/my-other-project

# 2. Start the AI assistant
ait

# 3. Inside the chat, use 'dump' to send the project's code for analysis
# The '.' refers to your current directory (~/dev/my-other-project)
a "Please review this project for potential bugs: $(dump .)"

# Or, use the interactive helper to choose a task
h  # --> select "code-review" or "analyze-project" from the menu
```

### 4. Exit
Type `exit` or press `Ctrl+D` to leave the chat session.

## 📝 Notes

*   **Token Caching**: Access tokens are cached in a temporary directory (`$TMPDIR` or `/tmp`) to speed up sequential requests.
*   **Backups**: Every response triggers a versioned backup of the history file.
*   **Metrics**: Token usage is logged in `<filename>.log` alongside the JSON history.

## 📜 License
[MIT](LICENSE)
