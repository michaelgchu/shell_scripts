#!/usr/bin/env python3
Script_Name    = 'Regex Learning Tool'
Script_Version = '0.5.1'
Script_Description = \
'''This program provides a simple way to write a regular expression and see what portions of text it will match.
It is meant as a tool to help you learn regex :)

# How to Use:
- enter a pattern into the top text field
- use the checkboxes to set any flags to use
- enter your text content into the large textbox
- click the "Find matches" button or press ENTER within the pattern field
The tool will highlight all matches

# Additional features:
You can load sample patterns from the **Help** menu.
You can get some working Python3 code from the **File** menu.
'''
'''
Author: Michael G Chu - https://github.com/michaelgchu
Last updated: May 12 2024
You may need to install Python's Tkinter package. On Debian Linux:
    sudo apt install python3-tk
On RHEL:
    sudo yum install python3-tkinter

TODO:
- add option for live updates as you modify pattern or content
- add hover tooltips for flags
- add search & replace ability

References
https://stackoverflow.com/questions/23435648/how-i-can-change-the-background-color-and-text-color-of-a-textbox-done-with-tkin
https://tkdocs.com/tutorial/text.html
https://stackoverflow.com/questions/14824163/how-to-get-the-input-from-the-tkinter-text-widget
https://stackoverflow.com/questions/16996432/how-do-i-bind-the-enter-key-to-a-function-in-tkinter
https://stackoverflow.com/questions/4072150/how-to-change-a-widgets-font-style-without-knowing-the-widgets-font-family-siz
https://stackoverflow.com/questions/48731746/how-to-set-a-tkinter-widget-to-a-monospaced-platform-independent-font
https://stackoverflow.com/questions/66767590/obtaining-font-object-from-a-tkinter-widget
https://stackoverflow.com/questions/56861843/change-size-of-tkinter-messagebox
https://stackoverflow.com/questions/63099026/fomatted-text-in-tkinter
'''

import tkinter as tk
from tkinter import messagebox
import tkinter.font as tkFont
import re

#%% Script Configuration / Globals setting

GUI_BG_Colour = '#efefef' # The background colour for most elements in the GUI
GUI_Width = 600
GUI_Height = 350

# What to highlight the text that matches
highlight_colours = ['cyan', 'yellow'] # 2nd value will show first

# Establish our global var that stores the Tkinter root object
root = None

pattern_samples = [
    ('Find capital letters', '[A-Z]', 'g'),
    ('Find groups of 4 or more letters', '[A-Z]{4,}', 'gi'),
    ('Find cash or bucket or 3 letter words with A in the middle', r'cash|bucket|\b\wa\w\b', 'gi'),
    ('Find North American phone numbers, eg +1-416-123-4567', r'(?:\+1-)?\d{3}-\d{3}-\d{4}', 'g'),
    ('Find double words', r'\b([A-Z]+) +\1\b', 'gi'),
    ('Find words appearing twice anywhere', r'\b([A-Z]+)\b(?=.*?\1\b)', 'gis'),
]


#%% These are all the functions to provide key interactivity in the Tk application

def show_help():
    '''Shows info about the program in a custom message box'''
    show_popup_message(f"About {Script_Name} (v{Script_Version})",
                       Script_Description, True)


def report_status(selfie, message, category='info'):
    '''Updates the
    <statusmsg> Tk Label in the GUI.  The optional category parameter dictates
    the formatting: "info" is normal; "error" makes the text red.'''
    #print(message)
    if category.lower() == 'error':
        selfie.statusmsg.configure(foreground='red')
    else:
        selfie.statusmsg.configure(foreground='black')
    selfie.av_statusmsg.set(message)
    selfie.statusmsg.update() # run this so it takes effect immediately


def begin_payload(selfie):
    '''Ensure all inputs are provided, then kick off the Payload'''
    try:
        # Check that all mandatory fields are provided
        if not len(root.av_pattern.get()):
            report_status(selfie, 'No pattern provided', category='error')
            return False
        if not len(root.text.get('1.0', 'end-1c')):
            report_status(selfie, 'No text provided', category='error')
            return False
        rv = payload_action(selfie)
        if rv[0]:
            report_status(selfie, f'{rv[1]} matches')
            return True
        else:
            report_status(selfie, rv[1], category='error')
            return False
    except Exception as e:
        report_status(selfie, f"Error occurred: {e}", category='error')


def generate_sample_python_code(selfie):
    '''Generates a Python script the user can run to get the same results
    they see within this tool'''
    pattern = selfie.av_pattern.get()
    content = root.text.get('1.0', 'end-1c')
    if not len(pattern):
        pattern = 'Your pattern goes here'
    if not len(content):
        content = 'Your sample text goes here'
    flagstr = ''
    flags = []
    if selfie.av_flag_i.get() == 1:
        flags.append('re.IGNORECASE')
    if selfie.av_flag_m.get() == 1:
        flags.append('re.MULTILINE')
    if selfie.av_flag_s.get() == 1:
        flags.append('re.DOTALL')
    if len(flags):
        flagstr = ', flags=' + ' | '.join(flags)
    code = f'''import re
pattern = r"{pattern}"
content = """{content}"""
'''
    if selfie.av_flag_g.get() == 0:
        code += f'match = re.search(pattern, content{flagstr})'
        code += '\nif match:'
        code += "\n    print(f'Match: {match.start()}->{match.end()} = {match.group()}')"
    else:
        code += f'for i,match in enumerate(re.finditer(pattern, content{flagstr})):'
        code += "\n    print(f'Match {i}: {match.start()}->{match.end()} = {match.group()}')"
    print(code)
    show_popup_message('Sample Python code', code)


#%% THE REAL Meat of the tool is here

def payload_action(selfie):
    '''Search the provided content using the provided regular expression, and
    highlight any results back within the Text widget'''
    # Start by removing any existing tags used to highlight text
    for tag in selfie.text.tag_names():
        selfie.text.tag_delete(tag)
    # Yank out all required data from the Tk app:
    # Grab the pattern
    pattern = selfie.av_pattern.get()
    # Grab the text content. Specify 'end-1c' so we don't get a newline at end
    content = selfie.text.get('1.0', 'end-1c')
    # Grab all the flags we support
    flags = 0
    if selfie.av_flag_i.get() == 1:
        flags += re.IGNORECASE
    if selfie.av_flag_m.get() == 1:
        flags += re.MULTILINE
    if selfie.av_flag_s.get() == 1:
        flags += re.DOTALL
    # The global flag is special - impacts how we operate overall
    just1 = selfie.av_flag_g.get() == 0
    # Do the Thing.
    # Use re.finditer so we can easily iterate through all matches
    # Avoid using enumerate() so we can always reference var i even if no hits
    i = 0
    for match in re.finditer(pattern, content, flags=flags):
        i += 1
        # Grab start & end positions
        start_at = match.start()
        end_at = match.end()
        # Create a new tag for that range of characters and apply formatting
        # We can specify the straight character position without worrying about
        # logical lines
        tagname = 'match' + str(i)
        selfie.text.tag_add(tagname, f"1.0 + {start_at} chars", f"1.0 + {end_at} chars")
        selfie.text.tag_config(tagname, background=highlight_colours[i%2])
        if just1:
            return (True, 1)
    return (True, i)


#%% Begin the GUI building & startup
## Instantiating a new Tk instance for this application
# Note: will create every **interactive** element as an attribute of <root>.
# That makes the function calls easier(?)

root = tk.Tk()
root.title(Script_Name)
root.geometry(f'{GUI_Width}x{GUI_Height}')

# Set up the "named font" that will be used throughout. This allows for easy
# font resizing options
# The base Menu bar does not seem to resize in Windows - works ok in Linux.
# Testing shows that if you try to create a named font with an unavailable font
# family, tkinter will just use a default one instead of throwing an error
#   w = tk.Button(font = root.customFontMS)
#   wfont = tkFont.nametofont(w.cget('font'))
#   print(wfont.actual())
root.customFont   = tkFont.Font(family="TkDefaultFont", size=12)
root.customFontMS = tkFont.Font(family="Courier", size=12)  # family='TkFixedFont'

def font_bigger(selfie):
    '''Increase the size of all named fonts, which in turn increases the size of
    all widgets'''
    size = selfie.customFont['size']
    selfie.customFont.configure(size=size+2)
    size = selfie.customFontMS['size']
    selfie.customFontMS.configure(size=size+2)
def font_smaller(selfie):
    '''Decrease the size of all named fonts, which in turn decreases the size of
    all widgets'''
    size = selfie.customFont['size']
    selfie.customFont.configure(size=size-2)
    size = selfie.customFontMS['size']
    selfie.customFontMS.configure(size=size-2)


#%% Define the Application Variables, that the widgets can touch
# This var stores the regex pattern to apply
root.av_pattern = tk.StringVar()
root.av_pattern.set("[A-Z]")

# (you cannot tie the Text widget contents to an application var)

# This var stores a status message that can be set from any part of the app,
# and will be displayed in a Label widget.
root.av_statusmsg = tk.StringVar()
root.av_statusmsg.set('Ready!')

# These vars tie to checkbox elements in the GUI - global will be on
root.av_flag_g = tk.IntVar()
root.av_flag_i = tk.IntVar()
root.av_flag_m = tk.IntVar()
root.av_flag_s = tk.IntVar()
root.av_flag_g.set(1)
root.av_flag_i.set(0)
root.av_flag_m.set(0)
root.av_flag_s.set(0)


#%% Create the Menu system, which exists separately from the laid-out widgets
menubar = tk.Menu(root)

# create a pulldown menu, and add it to the menu bar
filemenu = tk.Menu(menubar, tearoff=0)
filemenu.add_command(label="+ font size", command=lambda: font_bigger(root), font=root.customFont)
filemenu.add_command(label="- font size", command=lambda: font_smaller(root), font=root.customFont)
filemenu.add_separator()
filemenu.add_command(label="Generate Python code",
                     command=lambda: generate_sample_python_code(root), font=root.customFont)
filemenu.add_separator()
filemenu.add_command(label="Exit", command=root.destroy, font=root.customFont)
menubar.add_cascade(label="File", menu=filemenu, font=root.customFont)

# create a pulldown menu, and add it to the menu bar
helpmenu = tk.Menu(menubar, tearoff=0)
helpmenu.add_command(label="About", command=show_help, font=root.customFont)
menubar.add_cascade(label="Help", menu=helpmenu, font=root.customFont)

## Set up the sample pattern entries
# Create the menu, which will be nested
samples = tk.Menu(helpmenu, tearoff=0)
# and add it as a cascade to the Help menu
helpmenu.add_cascade(label='Sample patterns', menu=samples, font=root.customFont)

def apply_sample_pattern(selfie, pattern, flags):
    '''Updates the pattern and flag Tk widgets using the provided values'''
    selfie.av_pattern.set(pattern)
    selfie.av_flag_g.set('g' in flags)
    selfie.av_flag_i.set('i' in flags)
    selfie.av_flag_m.set('m' in flags)
    selfie.av_flag_s.set('s' in flags)
    report_status(selfie, '=> /' + pattern + '/' + flags)
def _assignIt(p, f):
    return lambda: apply_sample_pattern(root, p, f)

# Add each of the sample patterns as a menu entry
for s in pattern_samples:
    samples.add_command(label=s[0], command=_assignIt(s[1], s[2]), font=root.customFont)

# display the menu bar
root.config(menu=menubar)


#%% Create & configure all of the main containers
top_frame    = tk.Frame(root, bg=GUI_BG_Colour, width=450, height=50, pady=3)
sec_frame    = tk.Frame(root, bg=GUI_BG_Colour, width=450, height=50, pady=3)
main_frame   = tk.Frame(root, bg=GUI_BG_Colour, width=450, height=300, pady=3)
btm_frame    = tk.Frame(root, bg=GUI_BG_Colour, width=450, height=45, pady=3)

# Configure our root/base setup
root.grid_rowconfigure(   2, weight=1)  # Allow the 3nd row to grow vertically
root.grid_columnconfigure(0, weight=1)  # Allow the (only) column to grow horizontally

# Layout the main frames
# Assign this to row 0, make it stretch horizontally
top_frame.grid( row=0, sticky="ew")
# Assign this to row 1, make it stretch horizontally
sec_frame.grid( row=1, sticky="ew")
# Assign this to row 2, make it stretch in all directions
main_frame.grid( row=2, sticky="nsew")
# Assign this to row 3, make it stretch horizontally
btm_frame.grid( row=3, sticky="ew")


#%% Create & lay out the widgets for the top frame
#   text field for the pattern

top_frame.grid_columnconfigure(1, weight=1)

pattern_label_slash1 = tk.Label(top_frame, text='/', bg=GUI_BG_Colour, font=root.customFontMS)
pattern_text  = tk.Entry(top_frame, textvariable=root.av_pattern, font=root.customFontMS)
pattern_label_slash2 = tk.Label(top_frame, text='/', bg=GUI_BG_Colour, font=root.customFontMS)

# This 'bind' this lets it activate on pressing ENTER
pattern_text.bind('<Return>', lambda x: begin_payload(root))

# Layout the widgets in the top frame
# By adding the 'sticky' option, we get the field to stretch out
pattern_label_slash1.grid(              row=1, column=0)
pattern_text.grid(               row=1, column=1, sticky='ew')
pattern_label_slash2.grid(              row=1, column=2)


#%% Create & lay out the widgets for the second frame
#   checkboxes below that for all the important flags that I know: g i m s

cb_flag_g = tk.Checkbutton(sec_frame, text='g', variable=root.av_flag_g, font=root.customFontMS)
cb_flag_i = tk.Checkbutton(sec_frame, text='i', variable=root.av_flag_i, font=root.customFontMS)
cb_flag_m = tk.Checkbutton(sec_frame, text='m', variable=root.av_flag_m, font=root.customFontMS)
cb_flag_s = tk.Checkbutton(sec_frame, text='s', variable=root.av_flag_s, font=root.customFontMS)

# Layout the widgets in the top frame
# By adding the 'sticky' option, we get the field to stretch out
cb_flag_g.grid(          row=0, column=0, padx=5) #, sticky='w')
cb_flag_i.grid(          row=0, column=1, padx=5)
cb_flag_m.grid(          row=0, column=2, padx=5)
cb_flag_s.grid(          row=0, column=3, padx=5)


#%% Create & lay out the widgets for the MAIN frame
###   a single text area that word wraps, with a vertical scroll bar

textScrollbar  = tk.Scrollbar(main_frame)
root.text = tk.Text(main_frame, yscrollcommand = textScrollbar.set, font=root.customFontMS)
root.text.insert(tk.END, '''There once was a man from Nantucket
Who kept kept all his cash in a bucket.
    But his daughter, named Nan,
    Ran away with a man
And as for the bucket, Nantucket.''')
textScrollbar.config(command=root.text.yview)

# Lay them out
## Allow the main bit to grow vertically
main_frame.grid_rowconfigure(   1, weight=1)
main_frame.grid_columnconfigure(0, weight=1)

textScrollbar.grid(       row=1, column=1, sticky='ns')
root.text.grid( row=1, column=0, sticky='nsew')


#%% Create & lay out the bottom widget(s) '''
###    a button to execute payload
###    a status field at the bottom to show # of matches

btm_frame.grid_columnconfigure(1, weight=1)

root.statusmsg = tk.Label(btm_frame, textvariable=root.av_statusmsg,
                          bg='white', wraplength=500, justify="center",
                          font=root.customFont)
root.statusmsg.grid(row=0, column=1, sticky='nsew')

begin_button = tk.Button(btm_frame, text='Find matches', font=root.customFont,
                                  command=lambda: begin_payload(root))
begin_button.grid(row=0, column=0, padx=5, sticky='e')



#%% A custom Text class & function for displaying large/formatted message windows

class RichTextRE(tk.Text):
    '''Extension to the Text widget. It defines 4 tags for formatting: bold,
    italic, h1, bullet. Bullets should be added using the  insert_bullet() method.
    This code was originally provided as "RichText" by Bryan Oakley on SO:
    https://stackoverflow.com/questions/63099026/fomatted-text-in-tkinter
    A new method  populate_re()  allows for automatic application of these tags,
    however there is no overlapping.  Additionally, the italic tag does not
    seem to work.
    '''
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        default_font = tkFont.nametofont(self.cget("font"))

        em = default_font.measure("m")
        default_size = default_font.cget("size")
        bold_font = tkFont.Font(**default_font.configure())
        italic_font = tkFont.Font(**default_font.configure())
        h1_font = tkFont.Font(**default_font.configure())

        bold_font.configure(weight="bold")
        italic_font.configure(slant="italic")
        h1_font.configure(size=int(default_size*1.5), weight="bold")

        self.tag_configure("bold", font=bold_font)
        self.tag_configure("italic", font=italic_font)
        self.tag_configure("h1", font=h1_font, spacing3=default_size, underline=True)

        lmargin2 = em + default_font.measure("\u2022 ")
        self.tag_configure("bullet", lmargin1=em, lmargin2=lmargin2)

    def insert_bullet(self, index, text):
        self.insert(index, f"\u2022 {text}", "bullet")

    def populate_re(self, content):
        '''Populate the Text widget with the content, using the 4 tags for
        formatting whenever the correct syntax is seen. Priority for tagging:
        List, Heading, Bold, Italics'''
        # Defining sub-patterns for every formatting we support. Each has 2 capture groups:
        # 1. first/outermost captures everything, so we consume it
        # 2. second/inner captures the value to actually display without the markdown
        all_patterns = r'''
            (^-\s(.+)$)         # List items, e.g. "- first bullet"
            |
            (^\#\s(.+)$)        # Heading, e.g. "# My First Subject"
            |
            (\*\*([^*]+?)\*\*)  # Bold, e.g. "**lol**"
            |
            (_([^_]+?)_)        # Italices, e.g. "_wut_"
        '''
        reo_all = re.compile(all_patterns, flags=re.X | re.MULTILINE)

        # Init position tracker so we know if any content gets skipped over
        lastpos = 0
        for match in re.finditer(reo_all, content):
            start_at = match.start()
            end_at = match.end()
            snippet = match.group() # what got matched (entire sub-string == outer capture group)
            if lastpos + 1 != start_at:
                # Unformatted content to load prior to this current match
                self.insert('end', content[lastpos:start_at])
            # Determine which kind got matched based on the populated Group
            if match.groups()[0]:   # List item
                self.insert_bullet('end', match.groups()[1] + '\n')
            elif match.groups()[2]: # Heading
                self.insert('end', match.groups()[3] + '\n', "h1")
            elif match.groups()[4]: # Bold
                self.insert('end', match.groups()[5], "bold")
            else:                   # Italic
                self.insert('end', match.groups()[7], "italic")
            lastpos = end_at
        # Finally, add any trailing Unformatted content
        self.insert('end', content[lastpos:])


def show_popup_message(title, message, auto_format=False):
    '''Regular window with an auto-sizing Text widget with scrollbar.
    This code was originally provided by user monty314thon on SO:
    https://stackoverflow.com/questions/56861843/change-size-of-tkinter-messagebox
    Now it uses the custom RichTextRE class instead of a standard Text widget,
    and if  auto_format=True  then it will apply some formatting using some
    basic markdown-type syntax (list, h1, bold, italic). '''
    popup = tk.Tk()
    # Set up the overall window
    popup.wm_title(title)
    popup.wm_attributes('-topmost', True)     # keeps popup above everything until closed.
#    popup.wm_attributes("-fullscreen", True)
    popup.configure(background='#4a4a4a')     # this is outer background colour
#    popup.wm_attributes("-alpha", 0.95)       # level of transparency
    popup.config(bd=2, relief=tk.FLAT)           # tk style

    tScrollbar = tk.Scrollbar(popup)
    # popup.text = RichText(popup, yscrollcommand = tScrollbar.set,
    popup.text = RichTextRE(popup, yscrollcommand = tScrollbar.set,
        foreground='white', background="#3e3e3e", relief=tk.FLAT, wrap='word')
    if auto_format:
        popup.text.populate_re(message)
    else:
        popup.text.insert(tk.END, message)
    popup.text.config(state=tk.DISABLED) # make it read-only
    tScrollbar.config(command=popup.text.yview)

    popup.text.grid(row=0, column=0, sticky='nsew')
    tScrollbar.grid(row=0, column=1, sticky='ns')
    popup.grid_columnconfigure(0, weight = 1)
    popup.grid_rowconfigure(   0, weight = 1)

    close_button = tk.Button(popup, text="Close", command=lambda: popup.destroy(),
        background="#4a4a4a", relief=tk.GROOVE, activebackground="#323232",
        foreground="#3dcc8e", activeforeground="#0f8954")
    close_button.grid(row=1, column=0)


#%% Start up the application

# After calling .mainloop(), the script holds till the app quits before proceeding
root.mainloop()

#EOF
