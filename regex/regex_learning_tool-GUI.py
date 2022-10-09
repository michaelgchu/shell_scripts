#!/usr/bin/env python3
Script_Name    = 'Regex Learning Tool'
Script_Version = '0.3.0'
Script_Description = " ".join([
        "This program provides a simple way to write a regular\n",
        "expression and see what portions of text it will match.\n",
        "It is meant as a tool to help you learn regex :)\n\n",
        "How to Use:\n",
        "- enter a pattern into the top text field\n",
        "- use the checkboxes to set any flags to use\n"
        "- enter your text content into the large textbox\n",
        "- click the \"Find matches\" button or press ENTER within the pattern field\n",
        "The tool will highlight all matches"])
Known_Bugs = " ".join([
        "Nothing yet ...\n",
        ])
''' 
Author: Michael G Chu - https://github.com/michaelgchu
Last updated: Oct 9 2022
You may need to install Python's Tkinter package. On Debian Linux, this should do it:
    sudo apt install python3-tk

TODO:
- Add font sizing options
- add option for live updates as you modify pattern or content
- add hover tooltips for flags
- add search & replace ability
- add ability to show/copy the Python commands to perform these actions

References
https://stackoverflow.com/questions/23435648/how-i-can-change-the-background-color-and-text-color-of-a-textbox-done-with-tkin
https://tkdocs.com/tutorial/text.html
https://stackoverflow.com/questions/14824163/how-to-get-the-input-from-the-tkinter-text-widget
https://stackoverflow.com/questions/16996432/how-do-i-bind-the-enter-key-to-a-function-in-tkinter
'''

import tkinter as tk
from tkinter import messagebox
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
    ('Find North American phone numbers, eg +1-416-123-4567', r'(?:\+1-)?\d{3}-\d{3}-\d{4}', 'g'),
    ('Find repeated words', r'\b([A-Z]+) +\1\b', 'gi'),
    ('Find words appearing twice', r'\b([A-Z]+)\b(?=.*?\1\b)', 'gis'),
]


#%% These are all the functions to provide key interactivity in the Tk application

def show_help():
    '''Shows info about the program in a message box'''
    messagebox.showinfo("About " + Script_Name,
        "v" + Script_Version + "\n\n" + Script_Description +
        "\n\n\nKnown Bugs:\n" + Known_Bugs)


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
### Instantiating a new Tk instance for this application
### Note: will create every **interactive** element as an attribute of <root>.
### That makes the function calls easier(?)

root = tk.Tk()
root.title(Script_Name)
root.geometry(f'{GUI_Width}x{GUI_Height}')

#%% Define the Application Variables, that the widgets can touch
### Also establish the event callbacks/hooks.

# This var stores the regex pattern to apply
root.av_pattern = tk.StringVar()
root.av_pattern.set("[A-Z]")

# ** Apparently you cannot tie the Text widget contents to an application var?
# # This var stores the TEXT to search within
# root.av_content = tk.StringVar()
# root.av_content.set("This is some sample text. Please try stuff out")

# This var stores a status message that can be set from any part of the app,
# and will be displayed in a Label widget.
root.av_statusmsg = tk.StringVar()
root.av_statusmsg.set('Ready!')

# These vars tie to checkbox elements in the GUI
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
filemenu.add_command(label="Exit", command=root.destroy)
menubar.add_cascade(label="File", menu=filemenu)

# create a pulldown menu, and add it to the menu bar
helpmenu = tk.Menu(menubar, tearoff=0)
helpmenu.add_command(label="About", command=show_help)
menubar.add_cascade(label="Help", menu=helpmenu)

## Set up the sample pattern entries
# Create the menu, which will be nested
samples = tk.Menu(helpmenu, tearoff=0)
# and add it as a cascade to the Help menu
helpmenu.add_cascade(label='Sample patterns', menu=samples)

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
    samples.add_command(label=s[0], command=_assignIt(s[1], s[2]))

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
## Assign this to row 0, make it stretch horizontally
top_frame.grid( row=0, sticky="ew")
## Assign this to row 1, make it stretch horizontally
sec_frame.grid( row=1, sticky="ew")
## Assign this to row 2, make it stretch horizontally
main_frame.grid( row=2, sticky="ew")
## Assign this to row 3, make it stretch horizontally
btm_frame.grid( row=3, sticky="ew")


#%% Create & lay out the widgets for the top frame
###    text field for the pattern

top_frame.grid_columnconfigure(1, weight=1)

pattern_label_slash1 = tk.Label(top_frame, text='/', bg=GUI_BG_Colour)
pattern_text  = tk.Entry(top_frame, textvariable=root.av_pattern)
pattern_label_slash2 = tk.Label(top_frame, text='/', bg=GUI_BG_Colour)

# This 'bind' this lets it activate on pressing ENTER
pattern_text.bind('<Return>', lambda x: begin_payload(root))

# Layout the widgets in the top frame
## By adding the 'sticky' option, we get the field to stretch out
pattern_label_slash1.grid(              row=1, column=0)
pattern_text.grid(               row=1, column=1, sticky='ew')
pattern_label_slash2.grid(              row=1, column=2)


#%% Create & lay out the widgets for the second frame
###    checkboxes below that for all the important flags that I know: g i m s

cb_flag_g = tk.Checkbutton(sec_frame, text='g', variable=root.av_flag_g)
cb_flag_i = tk.Checkbutton(sec_frame, text='i', variable=root.av_flag_i)
cb_flag_m = tk.Checkbutton(sec_frame, text='m', variable=root.av_flag_m)
cb_flag_s = tk.Checkbutton(sec_frame, text='s', variable=root.av_flag_s)

# Layout the widgets in the top frame
## By adding the 'sticky' option, we get the field to stretch out
cb_flag_g.grid(          row=0, column=0, padx=5) #, sticky='w')
cb_flag_i.grid(          row=0, column=1, padx=5)
cb_flag_m.grid(          row=0, column=2, padx=5)
cb_flag_s.grid(          row=0, column=3, padx=5)


#%% Create & lay out the widgets for the MAIN frame
###   a single text area that word wraps, with a vertical scroll bar

textScrollbar  = tk.Scrollbar(main_frame)
root.text = tk.Text(main_frame, yscrollcommand = textScrollbar.set)
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
                          bg='white', wraplength=500, justify="center")
root.statusmsg.grid(row=0, column=1, sticky='nsew')

begin_button = tk.Button(btm_frame, text='Find matches',
                                  command=lambda: begin_payload(root))


begin_button.grid(row=0, column=0, padx=5, sticky='e')


#%% Start up the application

# After calling .mainloop(), the script holds till the app quits before proceeding
root.mainloop()

#EOF
