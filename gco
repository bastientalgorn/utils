#!/bin/bash

function l_padding {
    str=$1
    num=`tput cols`
    v=$(printf "%-${num}s" "$str")
    echo "${v// /$str}"
}

function l_title {
    # Create some l_padding
    v="====== "$1" "`l_padding "="`
    #terminal width
    tw=`tput cols`
    # Cut excess
    v=`echo $v | head -c $tw`
    # Display
    echo -e $v
}

function l_help {
    #cat $0 | grep '^\s*#HELP' | sed 's/#HELP//g'
    sed -n 's/^\s*#HELP//p' < $0
}

function l_remove_color {
    sed_arg="s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"
    # No argument, assume the script is used after a pipe
    while read a; do
        echo $a | sed -r "$sed_arg" 
    done
}

if [[ $# = 0 ]]
then
    l_help
    exit
fi

nb_files=$( ls -1 | wc -l )
if [ "$nb_files" = "0" ]
then
    echo "The directory is empty"
    exit
fi

# How to edit the help
#=================================================
# Help for this script is in the script itself. 
# All the lines **starting** #HELP  will be printed # when the help needs to be displayed. 
# White spaces before #HELP  are allowed. 
# Indentation (either before of after #HELP ) is conserved.


#HELP ====================================================================================
#HELP gco (Grep COde)"
#HELP ====================================================================================
#HELP Search for a string in py, c, cpp, h, hpp, files, and in file names."
#HELP     gco element_of_code       # Search \"element_of_code\" in the current directory"
#HELP                               # and subdirectories. Case insensitive."
#HELP     gco -l element_of_code    # Use -l to display only matching file name"
#HELP     gco "a = b+1"             # Use "..." to search for a string containing spaces"
#HELP The search is recursive and not case sensitive."
#HELP ====================================================================================

# Default options
pmt_options="--exclude-dir=./pmt_linux_build/*" # --exclude-dir=./pmt_arch" #Exclude pmt files
extensions="c cc cpp h hpp"
grep_options='-nrFIi'
just_open_file="FALSE"
gco_list_file="$HOME/.gco_list.txt"
just_display_list="FALSE"
excludes=""
gco_editor=$EDITOR
use_remote="FALSE"


# READ OPTIONS
#========================================================
#HELP Options:

parse="TRUE"
while [ "$parse" == "TRUE" ]
do
key="$1"
case $key in
    --pmt)
        #HELP --pmt: includes pmt directory
        pmt_options=" " # Do not exclude pmt files
        shift
        ;;
    -i|--include)
        #HELP -i <ext>: searches ALSO in files with extension <ext>
        add_extension=$2
        echo "Add extenstion $add_extension"
        extensions=$extensions" "$add_extension
        shift
        shift   
        ;;
    -o|--only)
        #HELP -o <ext>: searches ONLY in files with extension <ext>
        add_extension=$2
        echo "Search only files with extension $add_extension"
        extensions=$add_extension
        shift
        shift   
        ;;
    -h)
        #HELP -h: searches ONLY in .h and .hpp files
        echo "Search only .h and .hpp files"
        extensions="h hpp"
        shift   
        ;;
    -n|--name)
        #HELP -n: searches ONLY in file names
        extensions=""
        shift   
        ;;
    -f|--file)
        #HELP -f <i>: opens the file on the i^th line of /tmp/.gco_list
        #HELP         <i> can be a list: 1 3 4 5
        #HELP         <i> can be a range: 1-5
        #HELP         <i> can be empty, in which case the 1st file is opened.
        shift
        file_number=$@
        #echo "Open file(s) $file_number"
        just_open_file="TRUE"
        silent="FALSE"
        shift
        ;;
    -l|--list)
        #HELP -l <i>: same as -f but simply display the list of files
        shift
        file_number=$@
        #echo "Open file(s) $file_number"
        just_open_file="TRUE"
        parse="FALSE" # Stop parsing
        silent="TRUE"
        #Overwrite editor (just display file list)
        gco_editor="echo"
        shift
        ;;    
    -a|--ll|--listall)
        #HELP -ll : same as -l but displays all the files
        shift
        file_number="all"
        #echo "Open file(s) $file_number"
        just_open_file="TRUE"
        silent="TRUE"
        #Overwrite editor (just display file list)
        gco_editor="echo"
        shift
        ;;
    -g|--g4)
        #HELP -g <i>: same as -f but with the "g4" editor
        shift
        just_open_file="TRUE"
        silent="FALSE"
        # Overwrite editor (open with g4)
        gco_editor="g4"
        ;;
    -r|--remote)
        #HELP -r: add " --remote" to gco editor
        shift
        use_remote="TRUE"
        ;;
    --gr)
        #HEAP --gr: same as -g -r
        shift
        use_remote="TRUE"
        just_open_file="TRUE"
        silent="FALSE"
        gco_editor="g4"
        ;;
    -e|--exclude)
        #HELP -e <word>: exclude lines matching <word>
        excludes=$excludes" -e "$2
        echo "Excludes do not work. Exit."
        exit
        shift
        shift
        ;;
    --log)
        #HELP --log: prints the log file
        just_display_list="TRUE"
        parse="FALSE" # Stop parsing
        shift
        ;;
    --help)
        #HELP --help: display help
        l_help
        exit
        ;;
    --)
        #HELP --: end of the gco options (same as for grep)
        #HELP     example: "gco -- --xx" will search for "--xx"
        parse="FALSE"
        shift
        break
        ;;
    -*|--*) 
        # unknown option
        echo "Unknown option \"$key\""
        echo "Exit."
        exit
        ;;
    *) 
        # Not an option
        parse="FALSE"
        break
        ;;
esac
done


if [ "$use_remote" = "TRUE" ]
then
    echo "Using remote"
    gco_editor=$gco_editor" --remote"
fi




if [ "$just_open_file" = "TRUE" ]
then
    # IF file number not set, use remaining arguments
    file_number=${file_number:-$@}
    # If no file number is provided, open first file
    file_number=${file_number:-"1"}

    if [ "$file_number" = "all" ]
    then
        nb_of_files=$(wc -l $gco_list_file | cut -f 1 -d ' ')
        file_number="1-$nb_of_files"
        #echo "nb_of_files: "$nb_of_files
        #echo "file_number: "$file_number
    fi

    # If file number contains "-", e.g. 1-4, then open all files from 1 to 4
    if [[ $file_number =~ [0-9]*-[0-9]* ]]
    then
        i1=$( echo $file_number | cut -f 1 -d '-' )
        i2=$( echo $file_number | cut -f 2 -d '-' )
        file_number=$( seq -s ' ' $i1 $i2 )
    fi

    # Open files 
    if [ "$silent" = "FALSE" ]; then
        echo "Open files $file_number with $gco_editor"
    fi
    file_list=""
    for n in $file_number
    do
        file=$( sed -n "$n{p;q;}" $gco_list_file | tr -s ' ' | cut -f 2 -d ' ' )
        if [ ! -z "$file" ]
        then
            if [ "$silent" = "FALSE" ]; then
                echo "Open $file"
            fi
            file_list=$file_list" "$file
        fi
    done
    $gco_editor $file_list &
    exit
fi



if [ "$just_display_list" = "TRUE" ]
then
    cat $gco_list_file
    exit
fi



if [ ! -z "$excludes" ]
then
    echo excludes:\"$excludes\"
fi

# Clean list file
> $gco_list_file



# Helper function
# Run the search and put the result in a tmp file
search_pattern=$1
function gco_search_helper(){
    ext=$1
    IFS=""
    #echo "pmt options:" $pmt_options
    unbuffer grep $grep_options --include=*.$ext $pmt_options --color=auto -- $search_pattern > /tmp/gco_tmp_$ext.txt
    touch /tmp/gco_tmp_$ext.end
}


# LOOP 1
#==============================
# Delete tmp files
# Launch jobs
rm /tmp/gco_tmp_* 2> /dev/null
for ext in $extensions
do
    gco_search_helper $ext &
done


# LOOP 2
#==============================
# Wait for end files
# Print result
for ext in $extensions
do
    l_title "Search in .$ext"
    while [ ! -f /tmp/gco_tmp_$ext.end ]
    do
      sleep 0.1
    done
    cat /tmp/gco_tmp_$ext.txt | tee -i -a $gco_list_file
    echo " "
done

# Clean tmp files
rm /tmp/gco_tmp_* 2> /dev/null


l_title "Search in file names"
# Note: we don't put that in the log file
find . -iname "*$1*" | grep --color=auto -- $@ 2>/dev/null
echo " "


# Display file list
#================================
l_title "File list "$gco_list_file
# Display the files where the kw appears the most.
# Sort by number of occurence of the file_name
# Keep top 15 searches
# Remove color
cat $gco_list_file | cut -f 1 -d ':' | uniq -c | sort -r | head -15 | l_remove_color  > $gco_list_file".tmp"

# Revert order of words, and put line number at the begining of each line
awk ' { t = $1; $1 = " "$2; $2 = " ("t")"; printf("#%02d %s\n", NR, $0); } ' $gco_list_file".tmp" > $gco_list_file

# Display list with color on $1
while read -r line
do
    line=$( echo $line | sed "s#$1#\\\\033[1;91m$1\\\\033[0m#" )
    echo -e $line
done < "$gco_list_file"
echo " "

# Display Words
#================================
#l_title "Word list "$gco_list_file
# Display the files where the kw appears the most.
# Sort by number of occurence of the file_name
# Keep top 15 searches
# Remove color
#cat $gco_list_file | l_remove_color | grep -o $search_pattern*[ ()] | sort -V | uniq -c

l_title "End of gco"





