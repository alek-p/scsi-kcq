#!/usr/sbin/dtrace -qCs
/* scsi_kcq.d - A script to print scsi sense data (errors) as it's received, with useful
 *           details such as execname issuing the failing command, what the command is,
 *           which device the command reached, what the KCQ is and the failed commands CDB. 
 *           Written using DTrace (NexentaOS_134f)
 *
 *
 *
 * 26-September-2012, ver 0.06
 *
 * USAGE: scsi_kcq.d [device]
 *
 *	scsi_kcq.d	   * print default output - live errors on all drives plus aggregation of errors at the end
 *	scsi_kcq.d sd2     * print default output only for disk sd2
 *
 * 	
 * FIELDS:
 *	DEVICE			name of the device the command was issue to
 *	EXECNAME		name of the executable which issued the command that offended the disk
 *	<*>SENSE(ERR) CATEGORY	a string representation of the mode sense key indicating type of error. * indicates descriptor format sense data
 *	KEY			mode sense key in hex
 *	ASC			additional sense code in hex
 *	ASCQ			additional sense code qualifier in hex
 *	TIMESTAMP		wallclock time when the sd_decode_sense:entry probe fired
 *	SCSI CMD		a string indicating what the offending  scsi command was
 *	CMD CDB			SCSI CDB for the command that generated the KCQ
 *	KCQ STRING		the translation of the key, asc, and ascq (KCQ) sense data fields
 *	COUNT			number of times the above fields were identical (aggregation on the above fields without CDB)
 *
 * NOTE: this script does not track "Predictive Failure Analysis threshold reached" KCQ.
 *
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License, Version 1.0 only
 * (the "License").  You may not use this file except in compliance
 * with the License.
 *
 * You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
 * or http://www.opensolaris.org/os/licensing.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at usr/src/OPENSOLARIS.LICENSE.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 *
 * Some parts were inherited from scsi.d and other DTT scripts.
 * Copyright 2012 Nexenta Systems Inc.
 * Author: Alek
 */

#pragma D option switchrate=10hz
#pragma D option defaultargs

/* increase the below variables if you're getting 'dynamic variable drops' under high load*/
#pragma D option dynvarsize=16m
#pragma D option cleanrate=303hz
	
dtrace:::BEGIN
{
	/*translation arrays*/
	scsi_ops[0x000, 0x0] = "TEST_UNIT_READY";
	scsi_ops[0x001, 0x0] = "REZERO_UNIT_or_REWIND";
	scsi_ops[0x003, 0x0] = "REQUEST_SENSE";
	scsi_ops[0x004, 0x0] = "FORMAT_UNIT";
	scsi_ops[0x005, 0x0] = "READ_BLOCK_LIMITS";
	scsi_ops[0x006, 0x0] = "Unknown(06)";
	scsi_ops[0x007, 0x0] = "REASSIGN_BLOCKS";
	scsi_ops[0x008, 0x0] = "READ(6)";
	scsi_ops[0x009, 0x0] = "Unknown(09)";
	scsi_ops[0x00a, 0x0] = "WRITE(6)";
	scsi_ops[0x00b, 0x0] = "SEEK(6)";
	scsi_ops[0x00c, 0x0] = "Unknown(0c)";
	scsi_ops[0x00d, 0x0] = "Unknown(0d)";
	scsi_ops[0x00e, 0x0] = "Unknown(0e)";
	scsi_ops[0x00f, 0x0] = "READ_REVERSE";
	scsi_ops[0x010, 0x0] = "WRITE_FILEMARK";
	scsi_ops[0x011, 0x0] = "SPACE";
	scsi_ops[0x012, 0x0] = "INQUIRY";
	scsi_ops[0x013, 0x0] = "VERIFY";
	scsi_ops[0x014, 0x0] = "Unknown(14)";
	scsi_ops[0x015, 0x0] = "MODE_SELECT(6)";
	scsi_ops[0x016, 0x0] = "RESERVE(6)";
	scsi_ops[0x017, 0x0] = "RELEASE(6)";
	scsi_ops[0x018, 0x0] = "COPY";
	scsi_ops[0x019, 0x0] = "ERASE(6)";
	scsi_ops[0x01a, 0x0] = "MODE_SENSE(6)";
	scsi_ops[0x01b, 0x0] = "START_STOP_UNIT";
	scsi_ops[0x01c, 0x0] = "RECEIVE_DIAGNOSTIC_RESULTS";
	scsi_ops[0x01d, 0x0] = "SEND_DIAGNOSTIC";
	scsi_ops[0x01e, 0x0] = "PREVENT_ALLOW_MEDIUM_REMOVAL";
	scsi_ops[0x01f, 0x0] = "Unknown(1f)";
	scsi_ops[0x020, 0x0] = "Unknown(20)";
	scsi_ops[0x021, 0x0] = "Unknown(21)";
	scsi_ops[0x022, 0x0] = "Unknown(22)";
	scsi_ops[0x023, 0x0] = "READ_FORMAT_CAPACITY";
	scsi_ops[0x024, 0x0] = "Unknown(24)";
	scsi_ops[0x025, 0x0] = "READ_CAPACITY(10)";
	scsi_ops[0x026, 0x0] = "Unknown(26)";
	scsi_ops[0x027, 0x0] = "Unknown(27)";
	scsi_ops[0x028, 0x0] = "READ(10)";
	scsi_ops[0x02a, 0x0] = "WRITE(10)";
	scsi_ops[0x02b, 0x0] = "SEEK(10)_or_LOCATE(10)";
	scsi_ops[0x02e, 0x0] = "WRITE_AND_VERIFY(10)";
	scsi_ops[0x02f, 0x0] = "VERIFY(10)";
	scsi_ops[0x030, 0x0] = "SEARCH_DATA_HIGH";
	scsi_ops[0x031, 0x0] = "SEARCH_DATA_EQUAL";
	scsi_ops[0x032, 0x0] = "SEARCH_DATA_LOW";
	scsi_ops[0x033, 0x0] = "SET_LIMITS(10)";
	scsi_ops[0x034, 0x0] = "PRE-FETCH(10)";
	scsi_ops[0x035, 0x0] = "SYNCHRONIZE_CACHE(10)";
	scsi_ops[0x036, 0x0] = "LOCK_UNLOCK_CACHE(10)";
	scsi_ops[0x037, 0x0] = "READ_DEFECT_DATA(10)";
	scsi_ops[0x039, 0x0] = "COMPARE";
	scsi_ops[0x03a, 0x0] = "COPY_AND_WRITE";
	scsi_ops[0x03b, 0x0] = "WRITE_BUFFER";
	scsi_ops[0x03c, 0x0] = "READ_BUFFER";
	scsi_ops[0x03e, 0x0] = "READ_LONG";
	scsi_ops[0x03f, 0x0] = "WRITE_LONG";
	scsi_ops[0x040, 0x0] = "CHANGE_DEFINITION";
	scsi_ops[0x041, 0x0] = "WRITE_SAME(10)";
	scsi_ops[0x04c, 0x0] = "LOG_SELECT";
	scsi_ops[0x04d, 0x0] = "LOG_SENSE";
	scsi_ops[0x050, 0x0] = "XDWRITE(10)";
	scsi_ops[0x051, 0x0] = "XPWRITE(10)";
	scsi_ops[0x052, 0x0] = "XDREAD(10)";
	scsi_ops[0x053, 0x0] = "XDWRITEREAD(10)";
	scsi_ops[0x055, 0x0] = "MODE_SELECT(10)";
	scsi_ops[0x056, 0x0] = "RESERVE(10)";
	scsi_ops[0x057, 0x0] = "RELEASE(10)";
	scsi_ops[0x05a, 0x0] = "MODE_SENSE(10)";
	scsi_ops[0x05e, 0x0] = "PERSISTENT_RESERVE_IN";
	scsi_ops[0x05f, 0x0] = "PERSISTENT_RESERVE_OUT";
	scsi_ops[0x07f, 0x0] = "Variable_Length_CDB";
	scsi_ops[0x07f, 0x3] = "XDREAD(32)";
	scsi_ops[0x07f, 0x4] = "XDWRITE(32)";
	scsi_ops[0x07f, 0x6] = "XPWRITE(32)";
	scsi_ops[0x07f, 0x7] = "XDWRITEREAD(32)";
	scsi_ops[0x07f, 0x9] = "READ(32)";
	scsi_ops[0x07f, 0xb] = "WRITE(32)";
	scsi_ops[0x07f, 0xa] = "VERIFY(32)";
	scsi_ops[0x07f, 0xc] = "WRITE_AND_VERIFY(32)";
	scsi_ops[0x080, 0x0] = "XDWRITE_EXTENDED(16)";
	scsi_ops[0x081, 0x0] = "REBUILD(16)";
	scsi_ops[0x082, 0x0] = "REGENERATE(16)";
	scsi_ops[0x083, 0x0] = "EXTENDED_COPY";
	scsi_ops[0x086, 0x0] = "ACCESS_CONTROL_IN";
	scsi_ops[0x087, 0x0] = "ACCESS_CONTROL_OUT";
	scsi_ops[0x088, 0x0] = "READ(16)";
	scsi_ops[0x08a, 0x0] = "WRITE(16)";
	scsi_ops[0x08c, 0x0] = "READ_ATTRIBUTES";
	scsi_ops[0x08d, 0x0] = "WRITE_ATTRIBUTES";
	scsi_ops[0x08e, 0x0] = "WRITE_AND_VERIFY(16)";
	scsi_ops[0x08f, 0x0] = "VERIFY(16)";
	scsi_ops[0x090, 0x0] = "PRE-FETCH(16)";
	scsi_ops[0x091, 0x0] = "SYNCHRONIZE_CACHE(16)";
	scsi_ops[0x092, 0x0] = "LOCK_UNLOCK_CACHE(16)_or_LOCATE(16)";
	scsi_ops[0x093, 0x0] = "WRITE_SAME(16)_or_ERASE(16)";
	scsi_ops[0x09e, 0x0] = "SERVICE_IN_or_READ_CAPACITY(16)";
	scsi_ops[0x0a0, 0x0] = "REPORT_LUNS";
	scsi_ops[0x0a3, 0x0] = "MAINTENANCE_IN_or_REPORT_TARGET_PORT_GROUPS";
	scsi_ops[0x0a4, 0x0] = "MAINTENANCE_OUT_or_SET_TARGET_PORT_GROUPS";
	scsi_ops[0x0a7, 0x0] = "MOVE_MEDIUM";
	scsi_ops[0x0a8, 0x0] = "READ(12)";
	scsi_ops[0x0aa, 0x0] = "WRITE(12)";
	scsi_ops[0x0ae, 0x0] = "WRITE_AND_VERIFY(12)";
	scsi_ops[0x0af, 0x0] = "VERIFY(12)";
	scsi_ops[0x0b3, 0x0] = "SET_LIMITS(12)";
	scsi_ops[0x0b4, 0x0] = "READ_ELEMENT_STATUS";
	scsi_ops[0x0b7, 0x0] = "READ_DEFECT_DATA(12)";
	scsi_ops[0x0ba, 0x0] = "REDUNDANCY_GROUP_IN";
	scsi_ops[0x0bb, 0x0] = "REDUNDANCY_GROUP_OUT";
	scsi_ops[0x0bc, 0x0] = "SPARE_IN";
	scsi_ops[0x0bd, 0x0] = "SPARE_OUT";
	scsi_ops[0x0be, 0x0] = "VOLUME_SET_IN";
	scsi_ops[0x0bf, 0x0] = "VOLUME_SET_OUT";
	scsi_ops[0x0d0, 0x0] = "EXPLICIT_LUN_FAILOVER";
	scsi_ops[0x0f1, 0x0] = "STORAGE_CONTROLLER";

	sense_keys[0x0] = "No Sense";
	sense_keys[0x01] = "Soft Error";
	sense_keys[0x02] = "Dev Not Ready";
	sense_keys[0x03] = "Medium Error";
	sense_keys[0x04] = "Hardware Error";
	sense_keys[0x05] = "Illegal Request";
	sense_keys[0x06] = "Unit Attention";
	sense_keys[0x07] = "Write Protect";
	sense_keys[0x08] = "Aborted Command";
	sense_keys[0x09] = "Vendor Unique";
	sense_keys[0x0a] = "Copy Aborted";
	sense_keys[0x0b] = "Aborted Command";
	sense_keys[0x0c] = "Equal";
	sense_keys[0x0d] = "Volume Overflow";
	sense_keys[0x0e] = "Other";
	sense_keys[0x0f] = "Reserved";
	
	kcq[0x01, 0x01,	0x0] = "Soft Error - Recovered Write error - no index";
	kcq[0x01, 0x02,	0x0] = "Soft Error - Recovered no seek completion";
	kcq[0x01, 0x03, 0x0] = "Soft Error - Recovered Write error - write fault";
	kcq[0x01, 0x09, 0x0] = "Soft Error - Track following error";
	kcq[0x01, 0x0b, 0x01] = "Soft Error - Temperature warning";
	kcq[0x01, 0x0c, 0x01] = "Soft Error - Recovered Write err with auto-realloc - reallocated";
	kcq[0x01, 0x0c, 0x03] = "Soft Error - Recovered Write err - recommend reassign";
	kcq[0x01, 0x12, 0x01] = "Soft Error - Recovered data without ECC using prev logical block ID";
	kcq[0x01, 0x12, 0x02] = "Soft Error - Recovered data with ECC using prev logical block ID";
	kcq[0x01, 0x14, 0x01] = "Soft Error - Recovered Record Not Found";
	kcq[0x01, 0x16, 0x0] = "Soft Error - Recovered Write err - Data Sync Mark Err";
	kcq[0x01, 0x16, 0x01] = "Soft Error - Recovered Write err - Data Sync Err - data rewritten";
	kcq[0x01, 0x16, 0x02] = "Soft Error - Recovered Write err - Data Sync Err - recommend rewrite";
	kcq[0x01, 0x16, 0x03] = "Soft Error - Recovered Write err - Data Sync Err - data auto-reallocated";
	kcq[0x01, 0x16, 0x04] = "Soft Error - Recovered Write err - Data Sync Err - recommend reassignment";
	kcq[0x01, 0x17, 0x0] = "Soft Error - Recovered data with no error correction applied";
	kcq[0x01, 0x17, 0x01] = "Soft Error - Recovered Read error - with retries";
	kcq[0x01, 0x17, 0x02] = "Soft Error -  Recovered data using positive offset";
	kcq[0x01, 0x17, 0x03] = "Soft Error - Recovered data using negative offset";
	kcq[0x01, 0x17, 0x05] = "Soft Error - Recovered data using previous logical block ID";
	kcq[0x01, 0x17, 0x06] = "Soft Error - Recovered Read err - without ECC, auto reallocated";
	kcq[0x01, 0x17, 0x07] = "Soft Error - Recovered Read err - without ECC, recommend reassign";
	kcq[0x01, 0x17, 0x08] = "Soft Error - Recovered Read err - without ECC, recommend rewrite";
	kcq[0x01, 0x17, 0x09] = "Soft Error - Recovered Read err - without ECC, data rewritten";
	kcq[0x01, 0x18, 0x0] = "Soft Error - Recovered Read error - with ECC";
	kcq[0x01, 0x18, 0x01] = "Soft Error - Recovered data with ECC and retries";
	kcq[0x01, 0x18, 0x02] = "Soft Error - Recovered Read error - with ECC, auto reallocated";
	kcq[0x01, 0x18, 0x05] = "Soft Error - Recovered Read error - with ECC, recommend reassign";
	kcq[0x01, 0x18, 0x06] = "Soft Error - Recovered data using ECC and offsets";
	kcq[0x01, 0x18, 0x07] = "Soft Error - Recovered Read error - with ECC, data rewritten";
	kcq[0x01, 0x1c, 0x0] = "Soft Error - Defect List not found";
	kcq[0x01, 0x1c, 0x01] = "Soft Error - Primary defect list not found";
	kcq[0x01, 0x1c, 0x02] = "Soft Error - Grown defect list not found";
	kcq[0x01, 0x1f, 0x0] ="Soft Error - Partial defect list transferred";
	kcq[0x01, 0x44, 0x0] = "Soft Error - Internal target failure";
	kcq[0x01, 0x5d, 0x0] = "Soft Error - PFA threshold reached";
	kcq[0x02, 0x04, 0x0] = "Not Ready - Cause not reportable";
	kcq[0x02, 0x04, 0x01] = "Not Ready - becoming ready";
	kcq[0x02, 0x04, 0x02] = "Not Ready - need initialise command (start unit)";
	kcq[0x02, 0x04, 0x03] = "Not Ready - manual intervention required";
	kcq[0x02, 0x04, 0x04] = "Not Ready - format in progress";
	kcq[0x02, 0x04, 0x09] = "Not Ready - self-test in progress";
	kcq[0x02, 0x31, 0x0] = "Not Ready - medium format corrupted";
	kcq[0x02, 0x31, 0x1] = "Not Ready - format command failed";
	kcq[0x02, 0x35, 0x2] = "Not Ready - enclosure services unavailable";
	kcq[0x02, 0x3A, 0x0] = "Not Ready - medium not present";
	kcq[0x02, 0x3A, 0x01] = "Not Ready - medium not present - tray closed";
	kcq[0x02, 0x3A, 0x02] = "Not Ready - medium not present - tray open";
	kcq[0x02, 0x4C, 0x0] = "Diagnostic Failure - config not loaded";
	kcq[0x03, 0x02,	0x0] = "Medium Error - No Seek Complete";
	kcq[0x03, 0x03,	0x0] = "Medium Error - write fault";
	kcq[0x03, 0x10,	0x0] = "Medium Error - ID CRC error";
	kcq[0x03, 0x11,	0x0] = "Medium Error - unrecovered read error";
	kcq[0x03, 0x11,	0x01] = "Medium Error - read retries exhausted";
	kcq[0x03, 0x11,	0x02] = "Medium Error - error too long to correct";
	kcq[0x03, 0x11,	0x04] = "Medium Error - unrecovered read error - auto re-alloc failed";
	kcq[0x03, 0x11,	0x0b] = "Medium Error - unrecovered read error - recommend reassign";
	kcq[0x03, 0x14,	0x01] = "Medium Error - record not found";
	kcq[0x03, 0x16,	0x0] = "Medium Error - Data Sync Mark error";
	kcq[0x03, 0x16,	0x04] = "Medium Error - Data Sync Error - recommend reassign";
	kcq[0x03, 0x19,	0x0] = "Medium Error - defect list error";
	kcq[0x03, 0x19,	0x01] = "Medium Error - defect list not available";
	kcq[0x03, 0x19,	0x02] = "Medium Error - defect list error in primary list";
	kcq[0x03, 0x19,	0x03] = "Medium Error - defect list error in grown list";
	kcq[0x03, 0x19,	0x00e] = "Medium Error - fewer than 50% defect list copies";
	kcq[0x03, 0x31,	0x0] = "Medium Error - medium format corrupted";
	kcq[0x03, 0x31,	0x01] = "Medium Error - format command failed";
	kcq[0x04, 0x01, 0x0] = "Hardware Error - no index or sector";
	kcq[0x04, 0x02, 0x0] = "Hardware Error - no seek complete";
	kcq[0x04, 0x03, 0x0] = "Hardware Error - write fault";
	kcq[0x04, 0x09, 0x0] = "Hardware Error - track following error";
	kcq[0x04, 0x11, 0x0] = "Hardware Error - unrecovered read error in reserved area";
	kcq[0x04, 0x16, 0x0] = "Hardware Error - Data Sync Mark error in reserved area";
	kcq[0x04, 0x19, 0x0] = "Hardware Error - defect list error";
	kcq[0x04, 0x19, 0x02] = "Hardware Error - defect list error in Primary List";
	kcq[0x04, 0x19, 0x03] = "Hardware Error - defect list error in Grown List";
	kcq[0x04, 0x31, 0x0] = "Hardware Error - reassign failed";
	kcq[0x04, 0x32, 0x0] = "Hardware Error - no defect spare available";
	kcq[0x04, 0x35, 0x01] = "Hardware Error - unsupported enclosure function";
	kcq[0x04, 0x35, 0x02] = "Hardware Error - enclosure services unavailable";
	kcq[0x04, 0x35, 0x03] = "Hardware Error - enclosure services transfer failure";
	kcq[0x04, 0x35, 0x04] = "Hardware Error - enclosure services refused";
	kcq[0x04, 0x35, 0x05] = "Hardware Error - enclosure services checksum error";
	kcq[0x04, 0x3e, 0x03] = "Hardware Error - self-test failed";
	kcq[0x04, 0x3e, 0x04] = "Hardware Error - unable to update self-test";
	kcq[0x04, 0x44, 0x0] = "Hardware Error - internal target failure";
	kcq[0x05, 0x1a, 0x0] = "Illegal Request - parm list length error";
	kcq[0x05, 0x20, 0x0] = "Illegal Request - invalid/unsupported command code";
	kcq[0x05, 0x21, 0x0] = "Illegal Request - LBA out of range";
	kcq[0x05, 0x24, 0x0] = "Illegal Request - invalid field in CDB";
	kcq[0x05, 0x25, 0x0] = "Illegal Request - invalid LUN";
	kcq[0x05, 0x26, 0x0] = "Illegal Request - invalid fields in parm list";
	kcq[0x05, 0x26, 0x01] = "Illegal Request - parameter not supported";
	kcq[0x05, 0x26, 0x02] = "Illegal Request - invalid parm value";
	kcq[0x05, 0x26, 0x03] = "Illegal Request - invalid field parameter - threshold parameter";
	kcq[0x05, 0x26, 0x04] = "Illegal Request - invalid release of persistent reservation";
	kcq[0x05, 0x2c, 0x0] = "Illegal Request - command sequence error";
	kcq[0x05, 0x35, 0x01] = "Illegal Request - unsupported enclosure function";
	kcq[0x05, 0x49, 0x0] = "Illegal Request - invalid message";
	kcq[0x05, 0x53, 0x0] = "Illegal Request - media load or eject failed";
	kcq[0x05, 0x53, 0x01] = "Illegal Request - unload tape failure";
	kcq[0x05, 0x53, 0x02] = "Illegal Request - medium removal prevented";
	kcq[0x05, 0x55, 0x0] = "Illegal Request - system resource failure";
	kcq[0x05, 0x55, 0x01] = "Illegal Request - system buffer full";
	kcq[0x05, 0x55, 0x04] = "Illegal Request - Insufficient Registration Resources";
	kcq[0x06, 0x28, 0x0] = "Unit Attention - not-ready to ready transition (format complete)";
	kcq[0x06, 0x29, 0x0] = "Unit Attention - POR or device reset occurred";
	kcq[0x06, 0x29, 0x01] = "Unit Attention - POR occurred";
	kcq[0x06, 0x29, 0x02] = "Unit Attention - SCSI bus reset occurred";
	kcq[0x06, 0x29, 0x03] = "Unit Attention - TARGET RESET occurred";
	kcq[0x06, 0x29, 0x04] = "Unit Attention - self-initiated-reset occurred";
	kcq[0x06, 0x29, 0x05] = "Unit Attention - transceiver mode change to SE";
	kcq[0x06, 0x29, 0x06] = "Unit Attention - transceiver mode change to LVD";
	kcq[0x06, 0x2a, 0x0] = "Unit Attention - parameters changed";
	kcq[0x06, 0x2a, 0x01] = "Unit Attention - mode parameters changed";
	kcq[0x06, 0x2a, 0x02] = "Unit Attention - log select parms changed";
	kcq[0x06, 0x2a, 0x03] = "Unit Attention - Reservations pre-empted";
	kcq[0x06, 0x2a, 0x04] = "Unit Attention - Reservations released";
	kcq[0x06, 0x2a, 0x05] = "Unit Attention - Registrations pre-empted";
	kcq[0x06, 0x2f, 0x0] = "Unit Attention - commands cleared by another initiator";
	kcq[0x06, 0x3f, 0x0] = "Unit Attention - target operating conditions have changed";
	kcq[0x06, 0x3f, 0x01] = "Unit Attention - microcode changed";
	kcq[0x06, 0x3f, 0x02] = "Unit Attention - changed operating definition";
	kcq[0x06, 0x3f, 0x03] = "Unit Attention - inquiry parameters changed";
	kcq[0x06, 0x3f, 0x05] = "Unit Attention - device identifier changed";
	kcq[0x06, 0x5d, 0x0] = "Unit Attention - PFA threshold reached";
	kcq[0x07, 0x27, 0x0] = "Write Protect - command not allowed";
	kcq[0x0b, 0x0, 0x0] = "Aborted Command - no additional sense code";
	kcq[0x0b, 0x1b, 0x0] = "Aborted Command - sync data transfer error (extra ACK)";
	kcq[0x0b, 0x25, 0x0] = "Aborted Command - unsupported LUN";
	kcq[0x0b, 0x3f, 0x0f] = "Aborted Command - echo buffer overwritten";
	kcq[0x0b, 0x43, 0x0] = "Aborted Command - message reject error";
	kcq[0x0b, 0x44, 0x0] = "Aborted Command - internal target failure";
	kcq[0x0b, 0x45, 0x0] = "Aborted Command - Selection/Reselection failure";
	kcq[0x0b, 0x47, 0x0] = "Aborted Command - SCSI parity error";
	kcq[0x0b, 0x48, 0x0] = "Aborted Command - initiator-detected error message received";
	kcq[0x0b, 0x49, 0x0] = "Aborted Command - inappropriate/illegal message";
	kcq[0x0b, 0x4b, 0x0] = "Aborted Command - data phase error";
	kcq[0x0b, 0x4e, 0x0] = "Aborted Command - overlapped commands attempted";
	kcq[0x0b, 0x4f, 0x0] = "Aborted Command - due to loop initialisation";
	kcq[0x0e, 0x1d,	0x0] = "Miscompare - during verify byte check operation";
	
	printf("Tracing... Hit Ctrl-C to end.\n\n");
	printf(" %-7s %-15s  %-20s %-4s %-4s %-5s %-21s %-30s %-16s\n", "DEVICE", "EXECNAME", "SENSE(ERR) CATEGORY", "KEY", "ASC", "ASCQ", "TIMESTAMP", "SCSI CMD", "CMD CDB");
}

/*save devname and execname to thread local var since later on they will not be easy to get*/
fbt:scsi:scsi_init_pkt:entry
/args[2] != 0/
{
	self->exec_name = execname;
	self->dev_name =  xlate <devinfo_t *>(args[2])->dev_name != "nfs" ? 
		xlate <devinfo_t *>(args[2])->dev_statname : "nfs";
	self->dev_name = self->dev_name !=  0 ? self->dev_name : "???";
}

/*save devname and execname to array with scsi_pkt address as key*/
fbt:scsi:scsi_init_pkt:return
/self->dev_name != 0/
{
	self->pkt = (struct scsi_pkt*)arg1;

	exec[self->pkt] = self->exec_name;
	self->exec_name = 0;
	dev_name[self->pkt] = self->dev_name;
	self->dev_name = 0;
}

/* macros to deferentiate between the two sense formats*/
#define	CODE_FMT_DESCR_CURRENT		0x2
#define	CODE_FMT_DESCR_DEFERRED		0x3

#define	SCSI_IS_DESCR_SENSE(sns_ptr) \
	(((((struct scsi_extended_sense *)(sns_ptr))->es_code) == \
	CODE_FMT_DESCR_CURRENT) || \
	((((struct scsi_extended_sense *)(sns_ptr))->es_code) == \
	CODE_FMT_DESCR_DEFERRED))

/* fires when fixed format sense data is seen */
fbt:sd:sd_decode_sense:entry
/(this->xp = (struct sd_xbuf *) arg2) && (!SCSI_IS_DESCR_SENSE((uint8_t *) this->xp->xb_sense_data)) && 
	(this->sense = (struct scsi_extended_sense *) this->xp->xb_sense_data) && this->sense->es_key &&
	(dev_name[(struct scsi_pkt *)arg3] == $$1 || $$1 == 0) /
{
	this->pkt = (struct scsi_pkt *)arg3;

	kcq_str[this->pkt] = kcq[this->sense->es_key, this->sense->es_add_code, this->sense->es_qual_code] != 0 ?
		kcq[this->sense->es_key, this->sense->es_add_code, this->sense->es_qual_code] : "Unknown KCQ";

	printf("\n %-7s %-15s  %-20s", dev_name[this->pkt], exec[this->pkt], sense_keys[this->sense->es_key]);
	printf(" %-4.2x %-4.2x %-5.2x %-21Y", this->sense->es_key, this->sense->es_add_code, this->sense->es_qual_code, walltimestamp);
}

/* fires when descriptor format sense data is seen */
fbt:sd:sd_decode_sense:entry
/(this->xp = (struct sd_xbuf *) arg2) && (SCSI_IS_DESCR_SENSE((uint8_t *) this->xp->xb_sense_data)) && 
	(this->sense_descr = (struct scsi_descr_sense_hdr *) this->xp->xb_sense_data) && this->sense_descr->ds_key &&
	(dev_name[(struct scsi_pkt *)arg3] == $$1 || $$1 == 0)/
{
	this->pkt = (struct scsi_pkt *)arg3;
	
	kcq_str[this->pkt] = kcq[this->sense_descr->ds_key, this->sense_descr->ds_add_code, this->sense_descr->ds_qual_code] != 0 ?
		kcq[this->sense_descr->ds_key, this->sense_descr->ds_add_code, this->sense_descr->ds_qual_code] : "Unknown KCQ";

	printf("\n %-7s %-15s *%-20s", dev_name[this->pkt], exec[this->pkt], sense_keys[this->sense_descr->ds_key]);
	printf(" %-4.2x %-4.2x %-5.2x %-21Y",	this->sense_descr->ds_key, this->sense_descr->ds_add_code, this->sense_descr->ds_qual_code, walltimestamp);
}

/* scsi cmd end*/
#define DESTROY_PROBE fbt:scsi:scsi_destroy_pkt:entry

DESTROY_PROBE
/(this->pkt = (struct scsi_pkt *)arg0) && kcq_str[this->pkt] != 0 && (dev_name[this->pkt] == $$1 || $$1 == 0)/
{
	this->cdb = (uchar_t *)this->pkt->pkt_cdbp;
	this->group = ((this->cdb[0] & 0xe0) >> 5);
}

DESTROY_PROBE
/this->pkt && this->group == 0 && kcq_str[this->pkt] != 0 && (dev_name[this->pkt] == $$1 || $$1 == 0)/
{
	this->sa = 0;
	this->cdblen = 6;
}

DESTROY_PROBE
/this->pkt && (this->group == 1 || this->group == 2) && kcq_str[this->pkt] != 0 && (dev_name[this->pkt] == $$1 || $$1 == 0)/
{
	this->sa = 0;
	this->cdblen = 10;
}

#define INT16(A, B) ( (((A) & 0x0ffL) <<  8) | ((B) & 0x0ffL))

DESTROY_PROBE
/this->pkt && this->group == 3 && kcq_str[this->pkt] != 0 && (dev_name[this->pkt] == $$1 || $$1 == 0)/
{
	this->sa = INT16(this->cdb[8], this->cdb[9]);
	this->cdblen = 32
}

DESTROY_PROBE
/this->pkt && this->group == 4 && kcq_str[this->pkt] != 0 && (dev_name[this->pkt] == $$1 || $$1 == 0)/
{
	this->sa = 0;
	this->cdblen = 16;
}

DESTROY_PROBE
/this->pkt && this->group == 5 && kcq_str[this->pkt] != 0 && (dev_name[this->pkt] == $$1 || $$1 == 0)/
{
	this->sa = 0;
	this->cdblen = 12;
}

DESTROY_PROBE
/this->pkt && this->group > 5 && kcq_str[this->pkt] != 0 && (dev_name[this->pkt] == $$1 || $$1 == 0)/
{
	this->sa = 0;
	this->cdblen = this->pkt->pkt_cdblen;
}

DESTROY_PROBE
/this->pkt && kcq_str[this->pkt] != 0 && (dev_name[this->pkt] == $$1 || $$1 == 0)/
{
	this->cmd = (scsi_ops[(uint_t)this->cdb[0], this->sa] == 0) ? 
		strjoin("Unknown CMD ", lltostr((uint_t)this->cdb[0])) : scsi_ops[(uint_t)this->cdb[0], this->sa];
	printf(" %-30s ",this->cmd);

	@sd_kcq[dev_name[this->pkt], exec[this->pkt], this->cmd, kcq_str[this->pkt]] = count();
}

/*printing variable length CDBs*/
#define PRINT_CDB(N) DESTROY_PROBE \
/this->pkt && kcq_str[this->pkt] != 0 && (this->cdblen > N) && (dev_name[this->pkt] == $$1 || $$1 == 0)/ \
{ \
	printf("%2.2x", this->cdb[N]); \
}

PRINT_CDB(0)
PRINT_CDB(1)
PRINT_CDB(2)
PRINT_CDB(3)
PRINT_CDB(4)
PRINT_CDB(5)
PRINT_CDB(6)
PRINT_CDB(7)
PRINT_CDB(8)
PRINT_CDB(9)
PRINT_CDB(10)
PRINT_CDB(11)
PRINT_CDB(12)
PRINT_CDB(13)
PRINT_CDB(14)
PRINT_CDB(15)
PRINT_CDB(16)
PRINT_CDB(17)
PRINT_CDB(18)
PRINT_CDB(19)
PRINT_CDB(20)
PRINT_CDB(21)
PRINT_CDB(22)
PRINT_CDB(23)
PRINT_CDB(24)
PRINT_CDB(25)
PRINT_CDB(26)
PRINT_CDB(27)
PRINT_CDB(28)
PRINT_CDB(29)
PRINT_CDB(30)
PRINT_CDB(31)
PRINT_CDB(32)
PRINT_CDB(33)

/* clean all dynamic vars */
DESTROY_PROBE
/this->pkt/ 
{
	kcq_str[this->pkt] = 0;
	dev_name[this->pkt] = 0;
	exec[this->pkt] = 0;
}

/* clean all dynamic vars */
DESTROY_PROBE
/self->pkt/ 
{
	kcq_str[self->pkt] = 0;
	dev_name[self->pkt] = 0;
	exec[self->pkt] = 0;
	self->pkt = 0;
}

dtrace:::END
{
	printf("\n %-7s %-15s %-30s %-50s %5s\n", "DEVICE", "EXECNAME", "SCSI CMD", "KCQ STRING", "COUNT");
	printa(" %-7s %-15s %-30s %-50s %5@d\n", @sd_kcq);
	printf("\nsee: http://en.wikipedia.org/wiki/KCQ\n");
}
