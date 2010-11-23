ENSIME TextMate Bundle
======================

See a preview video [here](http://www.youtube.com/watch?v=sIp-Xt3TvrI "here")

Using it
--------

**NOTICE**: You need to have an .ensime project file in the root of your project. For more information about this file please read the [ENSIME manual](http://aemon.com/file_dump/ensime_manual.html#tth_sEc3 "ENSIME manual") or modify the sample one below: 

Here's a sample .ensime file:
<pre><code>(:project-package "com.sidewayscoding" 
 :use-sbt t 
 :root-dir "/Users/Mads/dev/projects/functional_dictionary/")</code></pre>

Now open a file file in that project and hit ⌃⇧R and chose "Start ENSIME". This will start the ENSIME backend and the output will be written in a HTML output window. You can safely minimize this window now. Now initialize ENSIME by hitting ⌃⇧R and pick the command "Initialize ENSIME". This will send your project file to ENSIME and it will start analyzing your code. After a few seconds ENSIME is ready to help you out.

- **Refactoring**
  - Organize imports (⌃⇧H): This will organize your imports and remove any unused imports
  - Reformat Document (⌃⇧H): This will reformat the current document
  - Rename (⌃⇧H): This will rename the selected text.
- **Other**
  - Inspect (⌃⇧i): This will show a tooltip with the type of the expression under the caret. 
  - Type check project(⌃⇧V): This will type check your project. If there are any errors it will display a drop-down list with the errors. If you pick one of the items it will jump to that line in the file with the error.
  - Code completion (alt+esc): This will do code-completion or either types or methods depending on when you call it.


Installation 
------------

**NOTICE**: You need to have ENSIME installed. You can download it [here](https://github.com/downloads/aemoncannon/ensime/ensime_2.8.1-0.3.8.tar.gz "here"). Simply download it and unpack it anywhere you like. 

To install the bundle simply run the following in your terminal:

<pre><code>git clone https://github.com/mads379/ensime.tmbundle.git
open ensime.tmbundle</code></pre>

Add the shell variable ENSIME_HOME in TextMate -> Preferences... -> Advanced -> Shell Variables to the root of your ENSIME distribution (This would be the path to the folder you just unpacked). For me this is <code>/Users/Mads/dev/tools/emacs\_config/ensime\_2.8.1-0.3.8</code>

About
-----

This bundle takes advantage of the [ENSIME backend](https://github.com/aemoncannon/ensime "ENSIME backend") to bring IDE features to TextMate Scala projects.