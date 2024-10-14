#!/bin/sh


# Function to drop to a shell
drop_shell() {
	echo "Dropping to shell..."
	PS1="BOOTSCRIPTFAILED env # " exec sh
}

#
# trap ctrl-c and call ctrl_c()
#
trap ctrl_c INT

function ctrl_c() {
	echo "** Trapped CTRL-C. Please wait."
	drop_shell
	exit 0
}

#
# VARs
#

boot_entries=""
entry_counter=1
label=""
menu_label=""
linux=""
initrd=""
append=""
#
#
selected_entry=""

CONFIG_PATH="./syslinux.conf"

# Save the current IFS value
old_IFS=$IFS



#
# check_config() - Checks if the configuration file exists.
#
check_config() {
	if [ ! -f "$CONFIG_PATH" ]; then
		echo "File not found: $CONFIG_PATH"
		drop_shell
	fi
}

#
# store_entry() - populate boot entries list
#
store_entry() {
	if [ -n "$label" ]; then
		boot_entries="$boot_entries$entry_counter|$label|$menu_label|$linux|$initrd|$append;"
		entry_counter=$(expr "$entry_counter" + 1)
	fi
}

# Read the config file line by line
while IFS= read -r line; do
	# Trim leading whitespace (both spaces and tabs)
	line=$(echo "$line" | sed 's/^[[:space:]]*//')

	# Check for each configuration line
	case "$line" in
		LABEL\ *)
			# Store the previous entry before starting a new one
			store_entry
			# Start new entry with LABEL
			label="${line#LABEL }"
			menu_label=""
			linux=""
			initrd=""
			append=""
			;;
		MENU\ LABEL\ *)
			menu_label="${line#MENU LABEL }"
			;;
		LINUX\ *)
			linux="${line#LINUX }"
			;;
		INITRD\ *)
			initrd="${line#INITRD }"
			;;
		APPEND\ *)
			append="${line#APPEND }"
			;;
	esac
	# Restore the original IFS value
	IFS=$old_IFS
done < "$CONFIG_PATH"


#
# get_entry_details() - returns specific boot entry details by num in $1
#
get_entry_details() {
	# split by ; see store_entry func
	IFS=';'
	for entry in $boot_entries; do
		entry_num=${entry%%|*}
		if [ "$entry_num" -eq "$1" ]; then
			rest=${entry#*|}
			label=${rest%%|*}
			rest=${rest#*|}
			menu_label=${rest%%|*}
			rest=${rest#*|}
			linux=${rest%%|*}
			rest=${rest#*|}
			initrd=${rest%%|*}
			append=${rest#*|}

			echo "LABEL=$label"
			echo "MLABEL=${menu_label:-$label}"
			echo "LINUX=$linux"
			echo "INITRD=$initrd"
			echo "APPEND=$append"
			return
		fi
	done
	# Restore the original IFS value
	IFS=$old_IFS
}

#
# print_menu() - prints fancy table from boot list
#
print_menu() {
	# Print table header
	printf "+----+----------------------------------------------------------+\n"
	printf "| No | Boot Option											  |\n"
	printf "+----+----------------------------------------------------------+\n"

	# Use the list_entries function to fetch the list of entries
	# Split by semicolon
	IFS=';'
	for entry in $boot_entries; do
		# Extract entry number
		entry_num=${entry%%|*}
		rest=${entry#*|}
		# Extract the label
		label=${rest%%|*}
		rest=${rest#*|}
		# Extract menu label
		menu_label=${rest%%|*}

		# Use the menu label if present, otherwise use the label
		if [ -z "$menu_label" ]; then
			menu_label="$label"
		fi

		# Trim the menu label
		max_length=56
		if [ ${#menu_label} -gt $max_length ]; then
			menu_label="${menu_label:0:max_length-3}..."
		fi

		# Format the output with proper padding
		printf "| %2s | %-56s |\n" "$entry_num" "$menu_label"
	done

	# table bottom
	printf "+----+----------------------------------------------------------+\n"

	# Restore the original IFS value
	IFS=$old_IFS
}


#
# select_entry() - when accepts $1 will pass to global var your chose.
# when called without args will ask user then.
#

select_entry() {
	# Check arg
	if [ "$#" -gt 0 ]; then
		if [ "$1" -ge 1 ] && [ "$1" -lt "$entry_counter" ]; then
			selected_entry="$1"
			return 0
		else
			local entry_limit=$(expr $entry_counter - 1)
			echo "Invalid entry number: $1. Must be between 1 and $entry_limit."
			return 1
		fi
	fi

	# Interactive mode
	while true; do
		#print_menu
		echo "Select an entry number (1-$entry_counter) or 'q' to quit to shell: "
		read -r user_input

		# Allow quitting
		if [ "$user_input" = "q" ]; then
			drop_shell
		fi

		# Validate input
		if [ "$user_input" -ge 1 ] && [ "$user_input" -lt "$entry_counter" ]; then
			# Get and display the entry details
			#get_entry_details "$user_input"
			#break
			selected_entry="$user_input"  # Store the selected entry globally
			return 0
		else
			echo "Invalid input. Please try again."
		fi
	done
}


#
# in a way if something goes wrong with ucode
#

extract_main_initrd() {
	final_initrd=""

	# Check if initrd contains a comma
	if [ "${initrd#*,}" != "$initrd" ]; then
		# Get the first and second parts
		first_initrd="${initrd%%,*}"
		second_initrd="${initrd#*,}"

		# Check if the first image is intel-ucode.img
		case "$first_initrd" in
			*ucode*)
				# Use the second image (if it exists)
				final_initrd="$second_initrd"
				;;
			*)
				# Otherwise, use the first image
				final_initrd="$first_initrd"
				;;
		esac
	else
		# If there's no comma, just use the initrd as is
		final_initrd="$initrd"
		case "$final_initrd" in
			*ucode*)
				echo "Warning: Only ucode file specified. No valid initrd found."
				final_initrd=""
				;;
		esac
	fi

	# Optional: Check if the final_initrd path is valid
	if [ -n "$final_initrd" ] && [ ! -f "$final_initrd" ]; then
		echo "Warning: Specified initrd file does not exist: $final_initrd"
	fi

	# Update the initrd variable
	initrd="$final_initrd"
}




generate_kexec_command() {
	# call func & shut
 	{
		get_entry_details "$selected_entry"
	} > /dev/null 2>&1

	# test do not trust this
	{
		extract_main_initrd
	} > /dev/null 2>&1

	# Construct kexec command
	kexec_cmd="kexec -l \"$linux\" --initrd=\"$initrd\" --append=\"$append\""
	echo "$kexec_cmd"
}


#
# check_kexec_params() - some basic validation of generated line
#
# Example usage:
#
# check_kexec_params "$(generate_kexec_command)"
#
check_kexec_params() {
	testtt=$1

	# Extract kernel path
	case "$testtt" in
		*-l*)
			krnl="${testtt#*-l }"  # Remove everything up to and including '-l '
			krnl="${krnl%% *}"  # Remove everything after the first space
			krnl="${krnl#\"}"   # Remove leading quote
			krnl="${krnl%\"}"   # Remove trailing quote
			echo "Kernel: $krnl"
			;;
		*)
			echo "Error: Kernel option not found."
			#return 1
			;;
	esac

	# Extract intrdd path
	case "$testtt" in
		*--initrd=*)
			intrdd="${testtt#*--initrd=}"  # Remove everything up to and including '--intrdd='
			intrdd="${intrdd%% *}"		# Remove everything after the first space
			intrdd="${intrdd#\"}"		 # Remove leading quote
			intrdd="${intrdd%\"}"		 # Remove trailing quote
			echo "intrdd: $intrdd"
			;;
		*)
			echo "Error: intrdd option not found."
			#return 1
			;;
	esac

	# Extract appnd string
	case "$testtt" in
		*--append=*)
			appnd="${testtt#*--append=}"  # Remove everything up to and including '--appnd='
			appnd="${appnd#\"}"		# Remove leading quote
			appnd="${appnd%\"}"		# Remove trailing quote
			appnd="${appnd%%$'\n'*}"   # Removes everything after the first newline
			echo "appnd: $appnd"
			;;
		*)
			echo "Error: appnd option not found."
			#return 1
			;;
	esac

	#
}


#
# editme() - edit kexec command on the fly
#

# usage:
# editme "$(generate_kexec_command)"
# with brakets

editme() {
	# Set the editor to use (default to vi if not set)
	EDITOR="${EDITOR:-vi}"
	tmp_file=$(mktemp)

	# Write the input to the temporary file
	echo "$1" > "$tmp_file"

	# Use eval to ensure the editor runs in the foreground
	$EDITOR \"$tmp_file\"

	# Read the first line from the temp file and return it
	{
		read first_line_test
		echo "$first_line_test"
	} < "$tmp_file"

	# Optionally clean up the temporary file
	rm -f "$tmp_file"
}



#timeout_handler() {
#	echo "Timeout reached. Automatically selecting the first entry."
#	select_entry 1
#	exit
#	#selected_entry="1"
#}

#
# countdown_timer() - accept arg time in seconds.
#
# Usage:
#  if countdown_timer "$TIMEOUT"; then....
#

countdown_timer() {
	total_time=$1
	elapsed_time=0

	while [ "$elapsed_time" -lt "$total_time" ]; do
		remaining_time=$(expr "$total_time" - "$elapsed_time")
		printf "\r%02d seconds remaining (press ANYKEY to break)" "$remaining_time"

		sleep 1
		elapsed_time=$(expr "$elapsed_time" + 1)

		# Check if any input is available (non-blocking)
		if read -r -n 1 -t 0.1 input; then
			echo ""  # Move to a new line after user input
			return 1  # Input received before timeout
		fi
	done

	echo ""
	return 0  # Timeout reached
}


# main () {

# 	check_config
# 	store_entry

# 	TIMEOUT=$(grep -m 1 'TIMEOUT ' "$CONFIG_PATH" | grep -oE '[0-9]*')
# 	TIMEOUT="${TIMEOUT:-60}"
# 	echo "Timeout is set to: $TIMEOUT"
# 	# Start the timeout countdown in the background
# 	#echo "You have $TIMEOUT seconds to make a selection."

# 	if countdown_timer "$TIMEOUT"; then
# 		echo "Timeout reached."
# 		select_entry 1
# 			if [ -n "$selected_entry" ]; then
# 				echo "No input provided, defaulting to entry number: $selected_entry"
# 				#generate_kexec_command
# 				# load kexec
# 				eval $(generate_kexec_command)
# 				kexec -e
# 			fi
# 		exit
# 	else
# 		echo "Input received. Proceeding guided menu."
# 		while true; do
# 			print_menu
# 			select_entry

# 			   echo "kexec loaded cmdline: $(generate_kexec_command)"

# 				while true; do
# 				echo "Options:"
# 				echo "b) Boot selected"
# 				echo "e) Edit selected"
# 				echo "s) Drop to shell"
# 				echo "m) Return to menu"
# 				echo "q) Quit"

# 				# Prompt the user for an option
# 				read -r -p "Choose an option: " user_choice

# 				case "$user_choice" in
# 					b)
# 						echo "Booting with the command: $kexec_command"
# 						check_kexec_params "$kexec_command"
# 						kexec -e  # Execute the kexec command
# 						break
# 						;;
# 					e)
# 						editme "$kexec_command"
# 						;;
# 					s)
# 						drop_shell
# 						;;
# 					m)
# 						echo "Returning to the menu..."
# 						break  # Break the inner loop to return to the outer loop and reprint the menu
# 						;;
# 					q)
# 						echo "Exiting..."
# 						exit 0
# 						;;
# 					*)
# 						echo "Invalid option, please try again."
# 						;;
# 				esac
# 			done
#		# If the user selected 'b' to boot, we break out of the outer loop and exit
#		 if [ "$user_choice" = "b" ]; then
#			 break
#		 fi
# 		done



# 		# echo "Input received. Proceeding guided menu."

# 		# # Capture the output of the function
# 		# kexec_commandd=$(generate_kexec_command)

# 		# # Display the command and ask the user if they want to proceed
# 		# echo "Generated command: $kexec_commandd"
# 		# echo "To boot"
# 		# read answer

# 		# # Check user response
# 		# case "$answer" in
# 		# 	[Yy])
# 		# 		# Load the kexec command
# 		# 		eval "$kexec_commandd"
# 		# 		echo "Executing 'kexec -e'..."
# 		# 		kexec -e
# 		# 		;;
# 		# 	[Ee])
# 		# 		# Call the other function if the user chooses 'e'
# 		# 		other_function
# 		# 		;;
# 		# 	*)
# 		# 		echo "Aborting."
# 		# 		;;
# 		# esac
# 		# while true; do
# 		# 	print_menu

# 		# 	select_entry

# 		# 	kexec_command=$(generate_kexec_command)
# 		# 	echo "$kexec_command"

# 		# 	while true; do
# 		# 		echo "Options:"
# 		# 		echo "b) Boot selected"
# 		# 		echo "e) Edit selected"
# 		# 		echo "s) Drop to shell"
# 		# 		echo "m) Return to menu"
# 		# 		echo "q) Quit"

# 		# 		read -r -p "Choose an option: " user_choice

# 		# 		case "$user_choice" in
# 		# 			b)
# 		# 				echo "Booting with the command: $kexec_command"
# 		# 				#check_kexec_params "$kexec_command"
# 		# 				kexec -e  # Execute the kexec command
# 		# 				break
# 		# 				;;
# 		# 			e)
# 		# 				editme "$kexec_command"
# 		# 				;;
# 		# 			s)
# 		# 				drop_shell
# 		# 				;;
# 		# 			m)
# 		# 				echo "Returning to the menu..."
# 		# 				break  # Break the inner loop to return to the outer loop and reprint the menu
# 		# 				;;
# 		# 			q)
# 		# 				echo "Exiting..."
# 		# 				exit 0
# 		# 				;;
# 		# 			*)
# 		# 				echo "Invalid option, please try again."
# 		# 				;;
# 		# 		esac
# 		# 	done

# 		# 	# If the user selected 'b' to boot, we break out of the outer loop and exit
# 		# 	if [ "$user_choice" = "b" ]; then
# 		# 		break
# 		# 	fi
# 		# done

# 		#select_entry

# 		#if [ -n "$selected_entry" ]; then
# 		#	echo "You selected entry number: $selected_entry"
# 		#test=$(get_entry_details "$selected_entry")  # Show details for selected entry
# 		#echo $test
# 		#echo "kexec command is: "
# 		#	generate_kexec_command
# 		#
# 		#check_kexec_params "$(generate_kexec_command)"
# 		#editme "$(generate_kexec_command)"
# 		#fi

# 		#selected_entry="$input"
# 	 fi

# 	#print_menu
# 	#table=$(print_menu)
# 	#select_entry


# 	# set timouts


# 	# Display the table in a dialog box
# #dialog --clear --tab-correct  --no-collapse  --title "Boot Options" --msgbox "$table" 0 0

# # Prompt user for input
# #dialog --clear --inputbox "Please enter the number of the boot option you want to select:" 8 40 2>tmpfile

# # Get the user's choice from the temporary file
# #choice=$(<tmpfile)

# # Remove the temporary file
# #rm tmpfile

# # Output the user's choice
# #echo "You selected: $choice"



# 	# if [ -n "$selected_entry" ]; then
# 	# 	echo "You selected entry number: $selected_entry"
# 	# 	#test=$(get_entry_details "$selected_entry")  # Show details for selected entry
# 	# 	#echo $test
# 	# 	#echo "kexec command is: "
# 	# 	generate_kexec_command
# 	# 	#
# 	# 	#check_kexec_params "$(generate_kexec_command)"
# 	# 	#editme "$(generate_kexec_command)"
# 	# fi

# }

# main


#TODOS


	# if kexec not valid fallback
	# need to decide fallback

	# todo: --initrd=" ../intel-ucode.img,../initramfs-linux.img"





#
# text editor
#

# #!/bin/sh

# # Function to edit a variable
# edit_var() {
#     var_to_edit="$1"

#     # Hide cursor and disable echo
#     stty -echo

#     # Cursor position in the var_to_edit string
#     cursor_pos=$(expr $(echo -n "$var_to_edit" | wc -c))

#     # Function to display the current variable with a visible cursor indicator
#     display_var() {
#         # Clear the line and move cursor to the beginning
#         tput el

#         # Insert a visual cursor (underscore) at the correct position
#         left_part=$(echo "$var_to_edit" | cut -c1-$cursor_pos)
#         right_part=$(echo "$var_to_edit" | cut -c$(expr $cursor_pos + 1)-)
#         printf "%s_%s" "$left_part" "$right_part"
#     }

#     # Function to handle user input
#     handle_input() {
#         local char arrow

#         # Read one character
#         IFS= read -r -s -n 1 char

#         case "$char" in
#             $'\033') # Escape sequence (arrows and other special keys)
#                 IFS= read -r -s -n 2 arrow
#                 case "$arrow" in
#                     '[D') # Left arrow
#                         if [ "$cursor_pos" -gt 0 ]; then
#                             cursor_pos=$(expr $cursor_pos - 1)
#                         fi
#                         ;;
#                     '[C') # Right arrow
#                         if [ "$cursor_pos" -lt $(expr $(echo -n "$var_to_edit" | wc -c)) ]; then
#                             cursor_pos=$(expr $cursor_pos + 1)
#                         fi
#                         ;;
#                 esac
#                 ;;
#             "") # Enter key
#                 return 1
#                 ;;
#             $'\177') # Backspace
#                 if [ "$cursor_pos" -gt 0 ]; then
#                     left_part=$(echo "$var_to_edit" | cut -c1-$(expr $cursor_pos - 1))
#                     right_part=$(echo "$var_to_edit" | cut -c$(expr $cursor_pos + 1)-)
#                     var_to_edit="$left_part$right_part"
#                     cursor_pos=$(expr $cursor_pos - 1)
#                 fi
#                 ;;
#             *) # Printable characters
#                 left_part=$(echo "$var_to_edit" | cut -c1-$cursor_pos)
#                 right_part=$(echo "$var_to_edit" | cut -c$(expr $cursor_pos + 1)-)
#                 var_to_edit="$left_part$char$right_part"
#                 cursor_pos=$(expr $cursor_pos + 1)
#                 ;;
#         esac
#         return 0
#     }

#     # Main editing loop
#     while true; do
#     	clear
#     	echo ""
#         echo "Hello! You can now edit the variable. Press Enter to finish or Ctrl+C to exit."
#         tput cup 0 0  # Move cursor to the top left
#         display_var

#         if ! handle_input; then
#             break
#         fi
#     done

#     # Restore terminal settings
#     tput cnorm
#     stty echo
#     tput el
#     echo
#     echo "Final variable value: $var_to_edit"
# }

# # Call the function with the variable to edit
# edit_var "Initial Value"







# Guided menu function for user input
# Guided menu function for user input
guided_menu() {
	while true; do
		print_menu
		select_entry

		# Load the initial kexec command
		kexec_command=$(generate_kexec_command)
		echo ""
		echo "kexec loaded cmdline: $kexec_command"
		echo ""

		while true; do
			echo "Options:"
			echo ""
			echo "b) Boot selected"
			echo "e) Edit selected"
			echo "m) Return to menu"
			echo "q) Quit to shell"
			echo ""
			read -r -p "Choose an option (b/e/m/q): " user_choice

			case "$user_choice" in
				b|B)
					echo "Booting with the command: $kexec_command"
					eval "$kexec_command"
					kexec -e
					break  # Exit inner loop to break outer loop and exit
					;;
				e|E)
					#editme "$kexec_command"
					#echo "$kexec_command"
					# Call editme and update kexec_command
					#"editme "$kexec_command""

					#
					# Set the editor to use (default to vi if not set)
					EDITOR="${EDITOR:-vi}"
					tmp_file="/tmp/tempvar.txt"
					#tmp_file="$(mktemp)"

					# Write the input to the temporary file
					echo "$kexec_command" > "$tmp_file"

					# Use eval to ensure the editor runs in the foreground
					$EDITOR "$tmp_file"

					# Read the first line from the temp file and return it
					{
						read first_line_test
						#echo "$first_line_test"
						kexec_command="$first_line_test"
					} < "$tmp_file"

					# Optionally clean up the temporary file
					rm -f "$tmp_file"

					#
					echo ""
					echo "Updated kexec command: $kexec_command"
					echo ""
					;;
				m|M)
					echo "Returning to the menu..."
					break  # Back to the menu
					;;
				q|Q)
					echo "Exiting..."
					drop_shell
					;;
				*)
					echo "Invalid option, please try again."
					;;
			esac
		done

		# Exit if user chose 'b' to boot
		if [ "$user_choice" = "b" ] || [ "$user_choice" = "B" ]; then
			break
		fi
	done
}



main() {
	# Step 1: Validate configuration and store the selected entry
	check_config
	store_entry

	# Step 2: Extract and handle the timeout value
	TIMEOUT=$(grep -m 1 'TIMEOUT ' "$CONFIG_PATH" | grep -oE '[0-9]*')
	TIMEOUT="${TIMEOUT:-60}"
	echo "Timeout is set to: $TIMEOUT"

	# Step 3: Start the countdown timer
	if countdown_timer "$TIMEOUT"; then
		echo "Timeout reached, default entry will be selected."
		select_entry 1
		if [ -n "$selected_entry" ]; then
			echo "No input provided, defaulting to entry number: $selected_entry"
			eval $(generate_kexec_command)
 			kexec -e
		fi
		exit 0
	else
		echo "Input received. Proceeding to guided menu."
		guided_menu
	fi
}




# Run the main function
main
