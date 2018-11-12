

####################################################################

# This script is based on the idea of the Newton Raphson method to 
# find an approximation of the zero of a function.
# Asking to find a saving equal to a certain number K is the same as 
# asking when P(x) - K = 0, where P(x) is the leakage power of the design
# as a function of the number of HVT cells. Hence defining f(x) = P(x) - K
# we shift our problem to the research of the zeroes of the function f(x).


#########################################################################

suppress_message UITE-416
suppress_message LNK-041
suppress_message NED-045
suppress_message PTE-018
suppress_message PWR-246
suppress_message PWR-601

define_user_attribute fitness -class cell -type float


# take all LVT cells
set cells [get_cell -filter "lib_cell.threshold_voltage_group == LVT"]
set alt_cell_ref_name []
# create a collection with the library name of each used cell
set cur_cell_ref_name  [get_attribute $cells ref_name]
# create a collection with counterpart HVT cells
foreach j $cur_cell_ref_name {
	lappend alt_cell_ref_name [string replace $j 6 6 H] 
}

# get the name of each instance of a cell
set cell_name [get_attribute $cells full_name]

# obtain the leakage power of each lvt cell substitute with hvt and get again their laeakage
set LVT_leakage [get_attribute $cells leakage_power]
for {set i 0} {$i < [llength $cell_name]} {incr i} {
	size_cell [lindex $cell_name $i] [lindex $alt_cell_ref_name $i] 
}
update_power
set HVT_leakage [get_attribute $cells leakage_power]
for {set i 0} {$i < [llength $cell_name]} {incr i} {
	size_cell [lindex $cell_name $i] [lindex $cur_cell_ref_name $i] 
}

dict set cell_info  [lindex $cell_name 0] a


foreach cell $cell_name alt_cell $alt_cell_ref_name cur_cell $cur_cell_ref_name LVTp $LVT_leakage HVTp $HVT_leakage {
	
	# proper way to get the counterpart HVT cell but very slow
	#set alt_cell [filter_collection [get_alternative_lib_cells -libraries "CORE65LPH*" [get_attribute $cell full_name]] "full_name =~ *[string replace [get_attribute $cell ref_name] 6 6 H]"] 
	

	# get estimate report on swapping cell
	redirect -variable rpt {estimate_eco -type size_cell $cell -lib_cell $alt_cell}

	# extract information from report
	set data [split $rpt "\n"]
	set stage_delay []
	set slack []
	foreach line $data {
		if {[regexp {.*[\s]+([0-9]+\.[0-9]+)[\s]+([0-9]+\.[0-9]+)[\s]+([0-9]+\.[0-9]+)[\s]+([0-9]+\.[0-9]+)} $line tot m1 m2 m3 m4]== 1} {
			lappend stage_delay $m2
			lappend slack $m4
		}
	}

	# take the worst slack
	if { [lindex $slack 1] > [lindex $slack 3]} {
		set min_slack_cell [lindex $slack 3]
	} else {
		set min_slack_cell [lindex $slack 1]
	}
	
	
	# compute delay variation for rise and fall
	set delta_delay_rise [expr {[lindex $stage_delay 0] - [lindex $stage_delay 1]}]
	set delta_delay_fall [expr {[lindex $stage_delay 2] - [lindex $stage_delay 3]}]

	# select maximum vatiation in delay
	if {$delta_delay_fall > $delta_delay_rise} {
		set delta_delay_max $delta_delay_fall
	} else {
		set delta_delay_max $delta_delay_rise
	}

	# associate a value to each cell directly inside the class 
	set K [expr {($LVTp-$HVTp)*100000000/$delta_delay_max}]
	set_user_attribute [get_cell -filter "full_name == $cell"] fitness [expr {($K*$min_slack_cell)}] -quiet
	
	dict set cell_info  $cell [list $cur_cell $alt_cell $K]

}


# clean all unused variables
unset cells 
unset alt_cell_ref_name
unset cur_cell_ref_name
unset cell_name
unset LVT_leakage
unset HVT_leakage





# This function swaps the received collection of cells from LVT to HVT
proc swap_HVT { full_name } {
	global cell_info 

	foreach b $full_name {
			
			size_cell $b [lindex [dict get $cell_info $b] 1]
		
	}

}


# This function swaps the received collection of cells from HVT to LVT
# the collection received already contains the right name 
proc swap_LVT { full_name } {
	global cell_info	

	foreach b $full_name {
			size_cell $b [lindex [dict get $cell_info $b] 0]
	}

}



# This function is used for testing purposes only, it replaces all cells in a design 
# from HVT to LVT 
proc LVT_restore {} {
	
	# Get all HVT pins
	set cells [get_cell -filter "lib_cell.threshold_voltage_group == HVT"]
	# now cell_unmasked contains a collection of cells sorted from lower to higher slack
	# Get full name and reference name of each cell, we will need both to swap cells
	set cell_full_name [get_attribute $cells full_name]
 
 	# call a function to swap cells
	swap_LVT $cell_full_name

}


# This function gets the current error from the desired savings
proc get_error { start_power savings } {
	# get the current power
	set cur_power [get_attribute [get_design] leakage_power];
	
	#compute the savings
	set save [expr { ($start_power - $cur_power)/$start_power }]
	
	# compute how far away we are from the goal
	return [expr {$save - $savings}]
}



# NOT USED it makes the algorithm very heavy
proc update_fitness { cell_list } {
	# Get all LVT pins
	global cell_info

	set lvt_cells [get_cell -filter "lib_cell.threshold_voltage_group == LVT"]


 	foreach cell $cell_list {
 		set pin_tmp [get_pins -filter "@cell.full_name == $cell and direction == out"]
 		if { [sizeof_collection $pin_tmp] > 1} {
 			set max_slack [lindex [lsort -real [get_attribute $pin_tmp max_slack] ] 0] 
 		} else {
 			set max_slack [get_attribute $pin_tmp max_slack]
 		}
 		set K [lindex [dict get $cell_info $cell] 2]
		set_user_attribute [get_cell -filter "full_name == $cell"] fitness [expr {($K*$max_slack)}] -quiet
 	}

 	return [get_attribute [sort_collection $lvt_cells fitness] full_name]
	
}


# main function input a saving between 0 and 1
proc dualVth {args} {
	# TODO uncomment to see performances
	# get the start time, to evaluate the performances
	set t0 [clock clicks -millisec]

	# get the argument
	parse_proc_arguments -args $args results
	set savings $results(-savings)

	set cl [get_cell -filter "lib_cell.threshold_voltage_group == LVT"]

	set cell [sort_collection $cl fitness]

	# Get full name and reference name of each cell, we will need both to swap cells
	set cell_full_name [get_attribute $cell full_name]
	set cell_ref_name [get_attribute $cell ref_name]

	# Get the number of LVT cells in the circuit
	set L [llength $cell_full_name]

	# Get the start power needed to compute the savings
	set start_power [get_attribute [get_design] leakage_power]

	

	# Check trivial values of savings
	# savings = 1 -> change all cells
	# savings = 0 -> change nothing
	if { $savings  == 1} {
		# call the function to swap cells to HVT on all cells
		swap_HVT $cell_full_name
		
		# TODO uncomment for performance estimation
		# evaluate the elapsed time in seconds
		puts stderr "[expr {([clock clicks -millisec]-$t0)/1000.}] sec" ;# RS
		
		# return the maximum achievable savings
		return [expr {1 - [get_error $start_power $savings]}]

	} elseif { $savings == 0 } {
		
		# TODO uncomment for performance estimation
		# evaluate the elapsed time in seconds
		puts stderr "[expr {([clock clicks -millisec]-$t0)/1000.}] sec" ;# RS

		return 0
	}
	
	# Set the start error on the desired saving
	set error 0.0125

	# The algorithm needs always 2 points thus we set the starting points

	# First trivial point is zero cell swapped, i.e. the error is -savings
	set x1 0 
	set fx1 [expr {0 - $savings}]

	# As a second point we make a guess considering a linear appoximation
	# thus we exchange the percentage of cells corresponding to the saving that we want to find
	# This first guess could be improved to make the algorithm faster
	set x2 [expr { int(($savings*$L))}]

	# Set the two extrema of the interval of cell to swap
	# the extrema always start from the cells on the tail of the list
	# which are the one with greater slack 
	set left_bound [expr {$L - $x2}]
	set right_bound [expr {$L - $x1 -1}]

	# swap the computed range
	swap_HVT [lrange $cell_full_name $left_bound $right_bound] 
	

 	# get the error
 	set fx2 [get_error $start_power $savings]

 	# until we have a positive error and the current error is bigger than the desired one
 	# or the error is negative and the cell swapped are less than all the LVT cells 
 	# try to find a better solution
	while { ($x2 != $L & $fx2 < 0) | ($fx2 > $error &  $fx2 > 0) } {

			# in order to avoid an infinite loop the error range inceases at each iteration
			# this concept is taken from ageing 
			set error [expr {$error*2}]

			# set new number of cell to swap
			set x1 [expr {  int($x2 - ($fx2*($x2 - $x1)/($fx2 - $fx1)))  }]

			# compute the left bound

			set left_bound [expr {$L - $x1 -1}]

			# test if the left bound imply swapping more cells than the one we have
			set OOB [expr {$left_bound < -1}]
			if { $OOB } {
				# in this case put a limit to the left bound
				set left_bound -1
				# update also value of x1
				set x1 $L
			}

			# set the right bound
			set right_bound [expr {$L - $x2 -1}]


			# test if we need to swap more cells to HVT
			if { $x1 > $x2 } {
				
				# adjust the left bound
				incr left_bound
				# swap the necessary cells
				swap_HVT [lrange $cell_full_name $left_bound $right_bound] 
			
			# test if we need to swap back some cells to LVT
			} elseif { $x2 > $x1} {
				
				# adjust the right bound
				incr right_bound
				# in this case we invert the two exteremes of the interval
				swap_LVT [lrange $cell_full_name $right_bound $left_bound]

			# the new point x1 is equal to x2
			} else {
				# if the point remains the same between two iterations 
				# and the error is positive, simply accept the solution
				if { $fx2 > 0 } {
					set x1 $x2
					set fx1 $fx2
					break
				# the error is negative so check if
				# we already tried to swap all cells
				} elseif { !$OOB } {
					# if some cells are available give a little push 
					# since it is possible that the algorithm remain stuck
					# this  is caused by the fact that we are in a descrete domain 
					# and this algorithm is thought for continuous domain
					for {set i 0} {$i < 4 && $x1 < $L} {incr i} {
						incr x1
						set left_bound [expr {$left_bound - 1}]
					}
					incr left_bound
					swap_HVT [lrange $cell_full_name $left_bound $right_bound] 


				} else {
					# if we already tried to swapp all cells just accept the result
					set x1 $x2
					set fx1 $fx2
					break
				}
			
			}
			
			# get the new error
			set fx1 [get_error $start_power $savings]

			# to avoid errors if the new error is equal to the 
			# previous one make them different
			if { $fx1 == $fx2 } {
				
				set fx1 [expr {$fx2 + 1}]
			}

			#swap variable content
			set x2 $x1[set x1 $x2; lindex {}]
			set fx2 $fx1[set fx1 $fx2; lindex {}]
	}

	
	# TODO uncomment for performances estimation
	# evaluate the elapsed time in seconds
	puts stderr "[expr {([clock clicks -millisec]-$t0)/1000.}] sec" ;# RS

	# return the final saving
	return [expr {$fx2 + $savings}]
}

define_proc_attributes dualVth \
-info "Post-Synthesis Dual-Vth cell assignment" \
-define_args \
{
	{-savings "minimum % of leakage savings in range [0, 1]" lvt float required}
}

# all information have been found using the command
# list_attribute -application -class ClassName

# some useful attributes
# cell -> full_name, leakage_power
# pin -> arrival window, full name, cell, slack
# net -> full name

# Port: These are the primary inputs, outputs or IO’s of the design.

# Pin: It corresponds to the inputs, outputs or IO’s of the cells in the design

#Net: These are the signal names, i.e., the wires that hook up the design
#together by connecting ports to pins and/or pins to each other.

#Clock: The port or pin that is identified as a clock source. The
#identification may be internal to the library or it may be done using
#dc_shell-t commands.

#Library: Corresponds to the collection of technology specific cells that
#the design is targeting for synthesis; or linking for reference.



################################################################################




