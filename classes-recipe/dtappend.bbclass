# Process *.dtappend files for build-time dynamic device-tree handling.
# The format of a *.dtappend file is:
#   +-- dtappend file ---------------------------------+
#   | write whatever comments, information,            |
#   | or whatever else here -- ignored                 |
#   |---                                               |
#   | all following lines from here to EOF will be     |
#   | copied to the $KERNEL_DEVICETREE file, verbatim  |
#   +--------------------------------------------------+

FILESEXTRAPATHS:prepend := "${THISDIR}/dtappend:"

inherit kernel-arch

def remove_prefix(text, prefix):
    if text.startswith(prefix):
        return text[len(prefix):]
    return text

def find_dtappends_with_parms(d):
    unpackdir = d.getVar('UNPACKDIR')
    fetch = bb.fetch2.Fetch([], d)
    dtappend_list = []
    for url in fetch.urls:
        local = fetch.localpath(url)
        base, ext = os.path.splitext(os.path.basename(local))
        if ext not in [".dtappend"]:
            continue
        dtappend_list.append(remove_prefix(url,'file://'))
    return dtappend_list

do_dtappend() {
	set +e

	cd "${S}"
	oldifs="${IFS}"

	# find/verify the device-tree for the kernel
	# use the one defined in the conf/machine.conf file
	if [ -z "${KERNEL_DEVICETREE}" ]; then
		bbfatal "KERNEL_DEVICETREE not set"
	fi
	dtbfile_no_extension=$(echo "${KERNEL_DEVICETREE}" | rev | cut -d'.' -f2- | rev)
	dtsfile="arch/${ARCH}/boot/dts/${dtbfile_no_extension}.dts"
	if [ ! -f "${dtsfile}" ]; then
		bbfatal "file to append not found: ${S}/${dtsfile}"
	fi
	bbnote "device-tree file to append: ${dtsfile}"

	# generate a list of *.dtappend items from SRC_URI with parms
	dtappends_with_parms="${@' '.join(find_dtappends_with_parms(d))}"
	bbnote "list of dtappends_with_parms: ${dtappends_with_parms}"

	for dtappend_uri in ${dtappends_with_parms}; do
		bbnote "processing dtappend: ${dtappend_uri}"

		dtappend_uri_file="$(echo ${dtappend_uri} | cut -d';' -f1)"
		dtappend_uri_file_full_path="${UNPACKDIR}/${dtappend_uri_file}"
		dtappend_uri_file_no_extension=$(echo ${dtappend_uri_file} | rev | cut -d'.' -f2- | rev)

		# generate tag string from parms
		TAGSTR="${dtappend_uri_file}"
		parm_count=$(echo ${dtappend_uri} | tr -dc ';' | wc -c)
		parm_idx=1
		while [ ${parm_idx} -le ${parm_count} ]; do
			parm_idx=$(expr ${parm_idx} + 1)
			parm="$(echo ${dtappend_uri} | cut -d';' -f${parm_idx})"
			val="$(echo ${parm} | cut -d'=' -f2)"
			TAGSTR="${TAGSTR}-${val}"
		done

		# check if this *.dtappend has already been applied
		grep "// DTAPPEND from:${TAGSTR}" ${dtsfile} > /dev/null 2>&1
		if [ $? -ne 1 ]; then
			bbnote "'${dtsfile}' appears to already have dtappend:'${dtappend_uri_file}', skipping"
			continue
		fi

		# start processing each *.dtappend file
		# the file starts with a comment section ending with "---"
		_comment=1

		IFS=''
		while read -r LINE; do
			# comments - ignored
			if [ ${_comment} -eq 1 ]; then
				if [ "${LINE}" = "---" ]; then
					# end of comment
					# next section is device-tree snippet
					_comment=0

					# leave a tag so we know this *.dtappend has been processed
					echo "" >> ${dtsfile}
					echo "// DTAPPEND from:${TAGSTR}" >> ${dtsfile}
				else
					bbnote "COMMENT: ${LINE}"
				fi
				continue

			# device-tree snippet
			elif [ ${_comment} -eq 0 ]; then
				bbnote "appending '${LINE}' to '${dtsfile}'"
				echo "${LINE}" >> ${dtsfile}

			# how did we get here?!
			else
				bbnote "very strange to be here _comment:${_comment}"
				bbnote "LINE: ${LINE}"
			fi
		done <${dtappend_uri_file_full_path}

		# perform a `sed` on the ${dtsfile} for every parm
		parm_count=$(echo ${dtappend_uri} | tr -dc ';' | wc -c)
		parm_idx=1
		while [ ${parm_idx} -le ${parm_count} ]; do
			parm_idx=$(expr ${parm_idx} + 1)
			parm="$(echo ${dtappend_uri} | cut -d';' -f${parm_idx})"
			bbnote "    parm ${parm_idx}: ${parm}"
			search="$(echo ${parm} | cut -d'=' -f1)"
			replace="$(echo ${parm} | cut -d'=' -f2)"
			sed -i -e "s/%${search}%/${replace}/g" ${dtsfile}
		done
	done
	IFS="${oldifs}"
}

addtask dtappend before do_kernel_configme after do_patch
do_dtappend[depends] = "util-linux-native:do_populate_sysroot"
