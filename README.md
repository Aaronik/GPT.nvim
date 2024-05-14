# GPTModels - an LLM AI plugin for neovim

An AI plugin designed to tighten your neovim workflow with AI LLMs, focusing on **stability** and **user experience**.

* **Test first development** - This plugin focuses on clean, stable code. All features are well tested.
* **Developer UX in mind** - The goal is a simple, ergonomic interface. It's meant to be easy to pick up, not requiring any memorization. The tool "gets out of your way".

---

### Usage

This plugin offers two commands:

* `:GPTCode` - open a window designed to iterate on selections of code
      <details>
        <summary>See example of :GPTCode</summary>
        <img width="1271" alt="image of :GPTChat window" src="https://github.com/Aaronik/GPT.nvim/assets/1324601/3e642a48-ce56-4295-a5fa-368b523bab2e">
      </details>
* `:GPTChat` - open a chat window, like ChatGPT
      <details>
        <summary>See example of :GPTChat</summary>
        <img width="1271" alt="image of :GPTCode window" src="https://github.com/Aaronik/GPT.nvim/assets/1324601/ca6604af-302f-4a44-8964-bb683633031e">
      </details>

The code window is great for iterating on a selection of code.
The chat window is great for having a free form conversation.

---

### Features

* **Supports OpenAI and Ollama** - Local LLMs can be amazing as well. This plugin makes it super simple to switch between different models. I often get "second opinions" on code I'm getting LLM help with.
* **File inclusion** - The plugin uses telescope for a super clean file picker, and includes the files in the messages to the llm.
* **Background processing** - close the window while the AI responds, open the window and the response will be there.
* **Selection inclusion** - Both windows, when opened with selected text, bring that selected text into the window for inclusion in your llm request. Opening with a selection clears the old session automatically.
* **Filetype inclusion** - The file's extension is included in llm requests so you don't have to specify what kind of code it is when supplying smaller amounts of code
* **Request cancellation** - I often send a request to gpt-4 and then immediately realize I missed something critical and want to make the request again. This plugin offers Ctrl-c in that situation and immediately kills the job. That way you can save time and tokens, and stay more in the flow.
* **Super simple key commands** - Key commands are clearly labeled without you needing to toggle any windows.
* **UX in mind** - It's hard to enumerate the little things, but I hope and think you'll notice them as you use the plugin. Examples include keeping sessions across close in both windows, saving the prompt window after you type stuff before you send the request, so you can slowly build up the request, scrolls on llm responses unless you're in the window, so you can interact with the response before it's finished, responsive window resizing when terminal window changes size
* **Stability** - This was written TDD, and always will be. It uses emmylua types as best as I could figure out how to use them. It should be pretty stable, with everything tested thoroughly.
* **Opens prepopulated with prior sessions** - both windows open with your last session. The plugin makes it easy to iterate on a message.

### Thanks
Big thanks to @jackMort for the inspiration for the code window. I used [jackMort/ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim) for a long time before deciding to write this plugin.

#### TODO

* Use ctrl-w + hjkl to move between windows
* code needs C-y?
* Rename to something better than GPT. Models? TwoModel? Maybe GPT is good? AIModels?
* Make a readme fr
* Focus same buffer on nui exit?
* Prompt tests?
* Chat loading indicator?
* Add copilot support .. Very hard as it turns out
* Protect against opening windows many times?
* One really big integration flow for each window
* Figure out how to test nui border text and test all the titles
* If you open the code window, get a buncha code in there, then switch to a file of a different filetype, then open again, the syntax highlighting is lost
