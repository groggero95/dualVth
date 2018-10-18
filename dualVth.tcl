
####################################################################

# This script is based on the idea of the newton raphson method to 
# find an approximation of the zero of a function.
# Asking to find a saving equal to a certain number K is the same as 
# asking when P(x) - K = 0, where P(x) is the leakage power of the design
# as a function of the number of HVT cells. Hence defining f(x) = P(x) - K
# we shift our problem to the research of the zeroes of the function f(x).


#########################################################################



# suppres warning messages derivated from swapping cells
suppress_message UITE-416
suppress_message LNK-041
suppress_message NED-045
suppress_message PTE-018


# Set some handy text global variables
set hvt CORE65LPHVT_nom_1.20V_25C.db:CORE65LPHVT
set lvt CORE65LPLVT_nom_1.20V_25C.db:CORE65LPLVT

# This function swap the received collection of cells from LVT to HVT
proc swap_HVT { full_name ref_name} {
	global hvt

	foreach b $full_name c $ref_name {
			# the received collection have names of LVT cells so we 
			# need to replace a couple of letters to correctly replace a cell
			size_cell $b $hvt/[string replace $c 5 6 LH] 
		
	}

}

# This function swap the received collection of cells from HVT to LVT
# the collection received already contains the right name 
proc swap_LVT { full_name ref_name} {
	global lvt

	foreach b $full_name c $ref_name {
			size_cell $b $lvt/$c
	}

}


# This function is simila to the one above but it is used by nother function
# to restore all HVT cells to LVT again
proc swap_LVT_1 { full_name ref_name} {
	global lvt

	foreach b $full_name c $ref_name {
			# the received collection have names of HVT cells so we 
			# need to replace a couple of letters to correctly replace a cell 
			size_cell $b $lvt/[string replace $c 5 6 LL]

	}

}


# This function is used for testing porposes only, it replace all cells in a desing 
# from HVT to LVT 
proc LVT_restore {} {
	
	# Get all HVT pins
	set hvt_pins [get_pins -filter "@cell.lib_cell.threshold_voltage_group == HVT"]

	# Get the name of the pins 
	set pinname [get_attribute $hvt_pins full_name -quiet] 
	# eliminate multiple cells
	set cell_unmasked [get_attribute $hvt_pins cell]
	set cell [index_collection $cell_unmasked 0]
	append_to_collection cell $cell_unmasked -unique
	# now cell_unmasked contains a collection of cells sorted from lower to higher slack
	# Get full name and refernece name of each cell, we will need both to swap cells
	set cell_full_name [get_attribute $cell full_name]
	set cell_ref_name [get_attribute $cell ref_name]
 
 	# call a function to swap cells
	[swap_LVT_1 $cell_full_name $cell_ref_name]

}


# This function gets the current error from the desired savings
proc get_error { start_power savings } {
	# get the current power
	set cur_power [get_total_leakage_pwr];

	# consider the power difference between the start and current power
	set tmp1 [expr {10**[expr {int([lindex $cur_power 1]) - int([lindex $start_power 1])}]}]
	#puts $tmp1 
	
	#compute the savings
	set save [expr { ([lindex $start_power 0] - [lindex $cur_power 0]/$tmp1)/[lindex $start_power 0] }]
	
	# compute how far away we are from the goal
	return [expr {$save - $savings}]
}



# Get the leakage power through the command report_power
proc get_total_leakage_pwr {} {
    #-tee is used to echo the report
    #save the report_power in a variable
    redirect -variable power_log {report_power}
    # Search for the leakage power
    set num [regexp {Cell Leakage Power\s+=\s+(\d+\.\d+)e([+|-])(\d+)} $power_log match_str leakage_value leakage_sign leakage_exp]

    # remove zero padding, i.e. 08 is converted to 8
    # avoiding this step may cause some problems
    scan $leakage_exp %d leakage_exp

    # return the value and the exponent separately
    return [list $leakage_value $leakage_exp]
}



# main function input a saving between 0 and 1
proc dualVth {args} {
	# TODO uncomment to see performances
	# get the start time, to evluate the performancess
	set t0 [clock clicks -millisec]

	# get the argument
	parse_proc_arguments -args $args results
	set savings $results(-savings)

	# Get all LVT pins
	set lvt_pins [get_pins -filter "@cell.lib_cell.threshold_voltage_group == LVT"]
	# Sort the pin list by slack
	set sorted_pins_collection [sort_collection $lvt_pins {max_slack}]
	# Get the name of the pins from the sorted list
	set pinname [get_attribute $sorted_pins_collection full_name -quiet] 
	# eliminate multiple cells
	set cell_unmasked [get_attribute $sorted_pins_collection cell]
	set cell [index_collection $cell_unmasked 0]
	append_to_collection cell $cell_unmasked -unique
	# now cell_unmasked contains a collection of cells sorted from lower to higher slack
	# Get full name and refernece name of each cell, we will need both to swap cells
	set cell_full_name [get_attribute $cell full_name]
	set cell_ref_name [get_attribute $cell ref_name]

	# Get the number of LVT cells in the circuit
	set L [llength $cell_full_name]

	# Get the start power needed to compute the savings
	set start_power [get_total_leakage_pwr]

	# Check trivial values of savings
	# savings = 1 -> change all cells
	# savings = 0 -> change nothing
	if { $savings  == 1} {
		# call the function to swapp cells to HVT on all cels
		[swap_HVT $cell_full_name $cell_ref_name]
		
		# TODO uncomment for performances estimation
		# evaluate the elapsed time in seconds
		puts stderr "[expr {([clock clicks -millisec]-$t0)/1000.}] sec" ;# RS
		
		# return the maximum achievable savings
		return [get_error $start_power $savings]

	} elseif { $savings == 0 } {
		
		# TODO uncomment for performances estimation
		# evaluate the elapsed time in seconds
		puts stderr "[expr {([clock clicks -millisec]-$t0)/1000.}] sec" ;# RS

		return 0
	}
	
	# Set the start error on the desired saving
	set error 0.025

	# The algorithm need always 2 points thus we set the starting points

	# First trivial point is zero cell swapped, i.e. the error is -savings
	set x1 0 
	set fx1 [expr {0 - $savings}]

	# As a second point we make a guess considering a linear appoximation
	# thus we excahnge the percentage of cells corresponding to the saving that we want to find
	# This first guess could be improved to make the algorithm faster
	set x2 [expr { int(ceil($savings*$L))}]

	# Set the two extrems of the interval of cell to swap
	# the extremes always start from the cells on the tail of the list
	# which are the one with greater slack 
	set left_bound [expr {$L - $x2}]
	set right_bound [expr {$L - $x1 -1}]

	# swap the computed range
	[swap_HVT [lrange $cell_full_name $left_bound $right_bound] [lrange $cell_ref_name $left_bound $right_bound] ]

 	# get the error
 	set fx2 [get_error $start_power $savings]

 	# untill we have a positive error and the current error is bigger than the desired one
 	# or the error is negative and the cell swapped are less than all the LVT cells 
 	# try to find a better solution
	while { ($x2 != $L & $fx2 < 0) | ($fx2 > $error &  $fx2 > 0) } {

			# in order to avoid an infinite loop the error range inceases at each iteration
			# this concept is taken from ageing 
			set error [expr {$error*1.5}]

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


			# test if we need to swap more cell to HVT
			if { $x1 > $x2 } {
				
				# adjust the left bound
				incr left_bound
				# swap the necessary cells
				[swap_HVT [lrange $cell_full_name $left_bound $right_bound] [lrange $cell_ref_name $left_bound $right_bound] ]
			# test if we need to swap back some cells to LVT
			} elseif { $x2 > $x1} {
				
				# adjust the right bound
				incr right_bound
				# in this case we invert the two exteremes of the interval
				[swap_LVT [lrange $cell_full_name $right_bound $left_bound] [lrange $cell_ref_name $right_bound $left_bound] ]
			# the new point x1 is equal to x2
			} else {
				# if the point remains the same between two iterations 
				# and the error is positive sipmly accepts the solution
				if { $fx2 > 0 } {
					set x1 $x2
					set fx1 $fx2
					break
				# the erroer is negative so check if
				# we already tried to swap all cels
				} elseif { !$OOB } {
					# if some cells are available give a little push 
					# since it is possible that the algorithm remain stuck
					# this  is caused by the fact that we are in a descrete domain 
					# and this algorithm is thaught for continuous domain
					for {set i 0} {$i < 4 && $x1 < $L} {incr i} {
						incr x1
						set left_bound [expr {$left_bound - 1}]
					}
					incr left_bound
					[swap_HVT [lrange $cell_full_name $left_bound $right_bound] [lrange $cell_ref_name $left_bound $right_bound] ]
			
				} else {
					# if we already tried to swapp all cells just accepts the result
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
