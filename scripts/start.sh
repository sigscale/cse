#!/bin/bash

${ROOTDIR}/bin/run_erl -daemon /run/${NODENAME}/ log \
		"ERL_LIBS=lib exec ${ROOTDIR}/bin/start_erl \
				${ROOTDIR} ${RELDIR} ${START_ERL_DATA} 
				-boot_var OTPHOME . \
				+K true +A 32 +Bi \
				-sname ${NODENAME}"

