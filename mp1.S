
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score#, crosshairs_x, crosshairs_y

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		#: callee save
		pushl	%ebp
		movl	%esp, %ebp

		pushl	%ebx
		pushl	%esi
		pushl	%edi

		call update_missiles
		call update_bases
		call update_crosshairs

		#: callee restore
		popl	%edi
		popl	%esi
		popl	%ebx

		leave
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:

		movl	4(%esp), %edx 			#: arg
		movl	8(%esp), %eax 			#: cmd

		cmpl	$0, %eax
		jb 		invalid_cmd
		cmpl	$4, %eax
		ja 		invalid_cmd

		jmp 	*mp1_ioctl_jump_table(,%eax, 4)
		
	invalid_cmd:
		movl 	$-1, %eax 				#: return -1
		ret



# ----------------- Functions private to this file -------------------

# Calc the offset from the start of video memory
# Inputs: push stack - current node address(ecx)
# Return: offset from the start of video memory (%eax)
# Registers: Standard C calling convention (affected reg: eax, ecx, edx)
video_memory_offset:
		pushl	%ebp
		movl	%esp, %ebp
		movl	8(%ebp), %ecx

		movl	8(%ecx), %eax
		rorl	$16, %eax 				#: row #
		imulw	$80, %ax
		imulw	$2, %ax 				#: 80 * row * 2
		movl	4(%ecx), %edx
		rorl	$16, %edx 				#: col #
		imulw	$2, %dx					#: col * 2
		addw	%ax, %dx 				#: offset from the start of video memory
		xorl 	%eax, %eax
		movw	%dx, %ax				#: eax stores the offset

		leave
		ret

# Erase the missile in video memory
# Inputs: push stack - current node address(ecx)
# Return: offset from the start of video memory (%eax)
# Registers: Standard C calling convention (affected reg: eax, ecx, edx)
mp1_missile_erase:
		pushl	%ebp
		movl	%esp, %ebp
		movl	8(%ebp), %ecx
		
		pushl	%ecx 					#: push param
		call 	video_memory_offset		#: %eax stores the video memory offset
		addl	$4, %esp 				#: pop param

		xorl	%ecx, %ecx
		movl	$32, %ecx 				#: %cl store the ascii value of (space)

		#: erase, pass in space
		call 	mp1_poke				#: only changes %edx

		leave
		ret

# Delete the missile in linked list (*current node, *previous node)
# Inputs: push stack - 1. previous node address(edx). 2. current node address(ecx)
# Return: the address of next node (%eax)
# Registers: Standard C calling convention (affected reg: eax, ecx, edx)
mp1_missile_remove:
	pushl	%ebp
	movl	%esp, %ebp
	movl	8(%ebp), %ecx
	movl	12(%ebp), %edx
	#: check whether first node
	cmpl	$0, %edx 						
	jne		not_head

	movl 	(%ecx), %eax	
	movl 	%eax, mp1_missile_list			#: head = ecx->next

	pushl	%ecx 							#: push param
	call 	mp1_free
	addl 	$4, %esp 						#: pop param
	movl	mp1_missile_list, %eax 			#: eax pointing to new head
	jmp 	remove_end
	not_head:
		movl	(%ecx), %eax				
		movl	%eax, (%edx)				#: update previous node's NEXT pointer
		pushl	%ecx 						#: push param
		call 	mp1_free
		addl 	$4, %esp 					#: pop param
		movl	(%edx), %eax 				#: eax pointing to next node
	remove_end:
		leave
		ret

# Update the missile in linked list & video memory
# Registers: Standard C calling convention
update_missiles:
	#: callee save
	pushl	%ebp
	movl	%esp, %ebp

	pushl	%ebx
	pushl	%esi
	pushl	%edi
# ------------------------------------------------------------------------
	#: if empty list 
	cmpl	$0, mp1_missile_list
	je 		end_of_list_loop
	
	movl	mp1_missile_list, %ecx 		#: store address of head node to %ecx
	xorl 	%edx, %edx 					#: %edx=0 when %ecx pointing to head
	loop_linked_list:
	#: 1. if out of screen, remove from list
		cmpl	$0, 4(%ecx)
		jl 		remove_element
		cmpl	$79, 4(%ecx)
		jg 		remove_element
		cmpl	$0, 8(%ecx)
		jl 		remove_element
		cmpl	$24, 8(%ecx)
		jg 		remove_element
		jmp 	in_screen
	remove_element:
		pushl	%edx 					#: caller save & push param
		pushl	%ecx 					#: push param
		call 	mp1_missile_erase		#: erase in video memory first
		call 	mp1_missile_remove 		#: delete node, return %eax pointing to next node
		addl 	$4, %esp				#: pop param
		popl 	%edx 					#: caller restore & pop param

		movl	%eax, %ecx 				#: store returned next node to %ecx
		cmpl	$0, %ecx 				#: check last node
		je 		end_of_list_loop
		jmp 	loop_linked_list

	in_screen:
		#: if X != DEST_X or Y != DEST_Y, not exploding
		movl	4(%ecx), %eax
		cmpl 	%eax, 20(%ecx)
		jne 	not_exploding

		movl	8(%ecx), %eax
		cmpl 	%eax, 24(%ecx)
		jne 	not_exploding

	#: 2. if exploding
	exploding:
		pushl	%ecx 					#: caller save

		pushl	%ecx 					#: push param
		call 	missile_explode
		jnz		game_state_changed

		addl	$4, %esp				#: pop param
		popl 	%ecx 					#: caller restore
	#: if counted down to zero, erase in video memory & linked list
		decl	28(%ecx)
		cmpl	$0, 28(%ecx)
		je 		remove_element
		jmp 	redraw_explosion

	game_state_changed:
		addl	$4, %esp				#: pop param
		call 	mp1_notify_user
		popl 	%ecx 					#: caller restore
	#: if counted down to zero, erase in video memory & linked list
		decl	28(%ecx)
		cmpl	$0, 28(%ecx)
		je 		remove_element

	redraw_explosion:
	#: still exploding, redraw
		#: caller save
		pushl	%ecx 					#: backup %ecx

		pushl	%ecx 					#: push param
		call 	video_memory_offset		#: %eax stores the video memory offset
		addl	$4, %esp 				#: pop param

		xorl	%ecx, %ecx
		movb	$64, %cl 				#: %cl store the ascii value of (C)
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		#: caller restore
		popl	%ecx

		jmp 	check_last_node

	#: 3. if not exploding
	not_exploding:
		pushl	%ecx 					#: push param
		call 	mp1_missile_erase		#: returning %eax stores the offset
		addl 	$4, %esp 				#: pop param
		movl	%eax, %ecx 				#: restore current address

		#: update x, y of the node
		movl 	12(%ecx), %eax
		addl 	%eax, 4(%ecx)

		movl 	16(%ecx), %eax
		addl 	%eax, 8(%ecx)

		cmpl	$0, 4(%ecx)
		jl 		remove_element
		cmpl	$79, 4(%ecx)
		jg 		remove_element
		cmpl	$0, 8(%ecx)
		jl 		remove_element
		cmpl	$24, 8(%ecx)
		jg 		remove_element

		#: caller save
		pushl	%ecx 					#: backup %edx and %ecx

		pushl	%ecx 					#: push param
		call 	video_memory_offset		#: %eax stores the video memory offset
		addl	$4, %esp 				#: pop param

		movb	32(%ecx), %dl
		xorl	%ecx, %ecx
		movb	%dl, %cl 				#: %cl store the ascii value of (C)
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		#: caller restore
		popl	%ecx

	check_last_node:
		#: if last element of the list
		cmpl	$0, %ecx 				#: ecx == NULL
		je 		end_of_list_loop

		#: %edx store the previous node
		addl 	%ecx, %edx
		addl 	(%ecx), %ecx
		jmp 	loop_linked_list

	end_of_list_loop:

# ------------------------------------------------------------------------
	#: callee restore
	popl	%edi
	popl	%esi
	popl	%ebx

	leave
	ret

# draw the alive/dead base
# Inputs: push stack - 1. base_alive's current Byte(%bl)2. starting offset from the start of video memory(eax)
# Return: none
# Registers: Standard C calling convention (affected reg: eax, ecx, edx)
#: %eax - offset from the start of video memory
#: %ecx - store the string to be print
#: %edx - counter
draw_base:
	pushl	%ebp
	movl	%esp, %ebp

	movl 	8(%ebp), %eax 					#: offset
	movl	12(%ebp), %ecx 					#: temporary stores base_alive array's Byte
	cmpb	$0, %cl
	jne 	draw_alive

	draw_dead:
		movb	dead_base_pic, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		addl	$2, %eax
		movb	dead_base_pic+1, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		addl	$2, %eax
		movb	dead_base_pic+2, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		addl	$2, %eax
		movb	dead_base_pic+3, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		addl	$2, %eax
		movb	dead_base_pic+4, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		jmp 	end_draw_loop

	draw_alive:
		movb	base_pic, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		addl	$2, %eax
		movb	base_pic+1, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		addl	$2, %eax
		movb	base_pic+2, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		addl	$2, %eax
		movb	base_pic+3, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		addl	$2, %eax
		movb	base_pic+4, %cl
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

	end_draw_loop:
		leave
		ret


#: %eax - offset from the start of video memory
#: %ebx - store the base_alive array
update_bases:
	#: callee save
	pushl	%ebp
	movl	%esp, %ebp

	pushl	%ebx
	pushl	%esi
	pushl	%edi
# ------------------------------------------------------------------------
	movl	base_alive, %ebx 	#: store the 4 Bytes array in ebx

	#: draw first base
	#: 24*80*2+18*2 ~ 24*80*2+22*2 = 3876 Bytes ~ 3884 Bytes
	movl	$3876, %eax 		#: first base's starting offset
	pushl	%ebx 				#: push param
	pushl 	%eax 				#: push param
	call 	draw_base
	addl 	$8, %esp 			#: pop param

	rorl	$8, %ebx 			#: element of next index
	#: draw second base
	#: 24*80*2+38*2 ~ 24*80*2+42*2 = 3916 Bytes ~ 3924 Bytes
	movl	$3916, %eax 		#: first base's starting offset
	pushl	%ebx 				#: push param
	pushl 	%eax 				#: push param
	call 	draw_base
	addl 	$8, %esp 			#: pop param

	rorl	$8, %ebx 			#: element of next index
	#: draw third base
	#: 24*80*58*2 ~ 24*80*2+62*2 = 3956 Bytes ~ 3964 Bytes
	movl	$3956, %eax 		#: first base's starting offset
	pushl	%ebx 				#: push param
	pushl 	%eax 				#: push param
	call 	draw_base
	addl 	$8, %esp 			#: pop param

# ------------------------------------------------------------------------
	#: callee restore
	popl	%edi
	popl	%esi
	popl	%ebx

	leave
	ret

update_crosshairs:
		#: callee save
		pushl	%ebp
		movl	%esp, %ebp

		movl	crosshairs_y, %eax
		#rorl	$16, %eax 				#: row #
		imull	$80, %eax
		imull	$2, %eax 				#: 80 * row * 2

		movl	crosshairs_x, %edx
		#rorl	$16, %edx 				#: col #
		imull	$2, %edx				#: col * 2
		addl	%edx, %eax 				#: offset from the start of video memory
		#xorl 	%eax, %eax
		#movw	%dx, %ax				#: eax stores the offset

		#xorl	%ecx, %ecx
		movl	$88, %ecx 				#: %cl store the ascii value of (X)
		call 	mp1_poke 				#: redraw, inputs %eax, %cl

		#: callee restore
		leave
		ret


mp1_ioctl_startgame:
	#: callee save
	pushl	%ebp
	movl	%esp, %ebp

	movl	$0x00010101, base_alive
	movl	$0, mp1_score
	movl	$40, crosshairs_x
	movl	$12, crosshairs_y

	#: callee restore
	leave
	ret



#: %ecx - address of the newly-allocated memory
#: %edx - arg passed in, address struct * to read from
mp1_ioctl_addmissile:
	#: callee save
	pushl	%ebp
	movl	%esp, %ebp

	pushl 	$33						#: push param			
	call 	mp1_malloc				#: allocate 33 Bytes
	addl 	$4, %esp				#: pop param
	cmpl 	$-1, %eax 				#: eax stores address of the newly-allocated memory
	je 		fail_malloc

	movl 	%eax, %ecx 				#: ecx stores newly-allocated address
	movl 	8(%ebp), %edx 			#: edx stores arg
	#: caller save
	pushl 	%ecx
	#: push param
	pushl	$33						#: copy 33 bytes
	pushl 	%edx 					#: *from : arg
	pushl 	%eax 					#: *to
	call 	mp1_copy_from_user
	#: pop param
	addl 	$12, %esp
	#: callee restore
	popl 	%ecx
	cmpl 	$0, %eax
	jne 	fail_copy_from_user

	#: add missile to linked list
	cmpl 	$0, mp1_missile_list
	je 		first_node

	#: not first node
	movl 	mp1_missile_list, %eax
	movl 	%eax, (%ecx) 						#: initialize next pointer

	movl 	%ecx, mp1_missile_list				#: change the head
	movl 	$0, %eax 							#: return 0
	jmp 	done_addmissile

	first_node:
		movl 	%ecx, mp1_missile_list			#: change the head
		movl 	$0, (%ecx) 						#: initialize next pointer
		movl 	$0, %eax 						#: return 0
		jmp 	done_addmissile

	fail_copy_from_user:
		pushl 	%ecx 							#: push param: newly-allocated address
		call 	mp1_free
		addl 	$4, %esp 						#: pop param

	fail_malloc:
		movl 	$-1, %eax 						#: return -1
	
	done_addmissile:
		#: callee restore
		leave
		ret

mp1_ioctl_movexhairs:
	#: callee save
	pushl	%ebp
	movl	%esp, %ebp

	movl 	8(%ebp), %ecx 					#: load x, y change
	xorl	%eax, %eax
	movw 	%cx, %ax
	cmpl 	$0, %eax
	jne 	erase_cross
	
	x_is_0:
	rorl	$16, %ecx
	xorl	%eax, %eax
	movw 	%cx, %ax
	cmpl 	$0, %eax
	je 		done_movexhairs
	rorl	$16, %ecx 						#: recover ecx
	jmp 	erase_cross
	
	erase_cross:
	movl	crosshairs_y, %eax
	imull	$160, %eax		 		#: 80 * row * 2
	movl	crosshairs_x, %edx
	imull	$2, %edx				#: col * 2
	addl	%edx, %eax 				#: offset from the start of video memory

	pushl 	%ecx

	xorl	%ecx, %ecx
	movl	$32, %ecx 				#: %cl store the ascii value of (space)
	#: erase, pass in space
	call 	mp1_poke				#: only changes %edx

	#: check and re-update crosshairs_x, crosshairs_y
	popl	%ecx

	xorl	%eax, %eax
	movw 	%cx, %ax
	addl 	%eax, crosshairs_x

	rorl	$16, %ecx
	xorl	%eax, %eax
	movw 	%cx, %ax
	addl 	%eax, crosshairs_y

	cmp 	$0, crosshairs_x
	jl 		limit_x_lower
	cmpl	$79, crosshairs_x
	jg 		limit_x_upper
	jmp 	after_limit_x
	limit_x_lower:
		movl 	$0, crosshairs_x
		jmp 	after_limit_x
	limit_x_upper:
		movl 	$79, crosshairs_x

	after_limit_x:
		cmpl	$0, crosshairs_y
		jl 		limit_y_lower
		cmpl	$24, crosshairs_y
		jg 		limit_y_upper
		jmp 	done_movexhairs
	limit_y_lower:
		movl 	$0, crosshairs_y
		jmp 	done_movexhairs
	limit_y_upper:
		movl 	$24, crosshairs_y

	done_movexhairs:
		movl 	$0, %eax 				#: return 0
		#: callee restore
		leave
		ret



#: %eax - temp result 3-bit base status
#: %ecx - store 4 Bytes of base status
#: %edx - final result 4 Bytes status
mp1_ioctl_getstatus:
	#: callee save
	pushl	%ebp
	movl	%esp, %ebp

	xorl 	%edx, %edx 						#: clear %edx
	movl 	mp1_score, %eax 				#: load current score
	#: copy current score into the low 16-bits of edx
	movw 	%ax, %dx 						
	xorl 	%eax, %eax 						#: clear %eax

	movl 	base_alive, %ecx
	cmpb 	$0, %cl
	je 		first_base_dead
	addl 	$1, %eax
	first_base_dead:
	#: check second base
	rorl 	$8, %ecx
	cmpb 	$0, %cl
	je 		second_base_dead
	addl 	$2, %eax
	second_base_dead:
	#: check third base
	rorl 	$8, %ecx
	cmpb 	$0, %cl
	je 		third_base_dead
	addl 	$4, %eax
	third_base_dead:
	#: done calc result 3-bit base status in %eax
	rorl 	$16, %edx 						#: rotate right 16 bits
	#: copy base status to high-bits of edx
	movb	%al, %dl
	roll 	$16, %edx 						#: rotate left 16 bits, recover edx

	#: push param
	pushl 	$4 								#: copy 4 Bytes
	pushl 	%edx 							#: *from : result
	pushl 	8(%ebp) 						#: *to: to the address of memory to be written
	call 	mp1_copy_to_user
	#: pop param
	addl 	$12, %esp	
	cmpl 	$0, %eax
	jne 	fail_copy_to_user
	movl 	$0, %eax 					#: return 0
	jmp 	done_getstatus

	fail_copy_to_user:
		movl 	$-1, %eax 					#: return -1

	done_getstatus:
		#: callee restore
		leave
		ret


#: %ecx - current node
mp1_ioctl_endgame:
	#: callee save
	pushl	%ebp
	movl	%esp, %ebp

	movl	mp1_missile_list, %ecx 		#: store address of head node to %ecx
	
	endgame_loop:
		cmpl	$0, %ecx 				#: ecx == NULL
		je 		done_endgame

		pushl	$0 						#: push param : 0 indicate current is head node
		pushl	%ecx 					#: push param
		call 	mp1_missile_remove 		#: delete node, return %eax pointing to next node
		addl 	$8, %esp				#: pop param

		movl	%eax, %ecx 				#: store returned next node to %ecx
		jmp endgame_loop
	done_endgame:
		#: callee restore
		leave
		ret


mp1_ioctl_jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame









