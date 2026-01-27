#!/bin/bash
# entrypoint.sh - Automatically detect GPUs and configure Slurm GRES

set -e

# Create logging function
log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Detect NVIDIA GPUs in the system
detect_gpus() {
	log "Detecting GPUs in the system..."

	# Check if nvidia-smi command is available
	if ! command -v nvidia-smi &>/dev/null; then
		log "WARNING: nvidia-smi command not available, cannot detect GPUs"
		return
	fi

	# Get GPU count
	GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)

	if [ "$GPU_COUNT" -eq 0 ]; then
		log "No GPUs detected in the system"
		return 1
	fi

	log "Detected $GPU_COUNT GPU device(s)"

	# Get GPU device paths
	GPU_DEVICES=$(ls -la /dev/nvidia* | grep -v nvidia-uvm | grep -v nvidia-modeset | grep -v nvidia-uvm-tools | grep -v nvidia-nvswitches | grep ^c | awk '{print $10}')

	# Get GPU model information
	GPU_NAMES=$(nvidia-smi --query-gpu=name --format=csv,noheader)

	log "Detected GPU models: $GPU_NAMES"
	return 0
}

# Generate gres.conf configuration
generate_gres_conf() {
	log "Generating gres.conf configuration..."

	# Get hostname
	HOSTNAME=$(hostname)

	# Create temporary file
	TEMP_GRES_CONF=$(mktemp)

	# Check if GPU devices exist
	if [ -z "$GPU_DEVICES" ]; then
		log "No GPU devices found, generating empty gres.conf"
		echo "# No GPU devices detected" >$TEMP_GRES_CONF
		return
	fi

	# Initialize temporary gres.conf file
	echo "# Auto-generated gres.conf - $(date)" >$TEMP_GRES_CONF

	# Create Device mapping for each GPU
	GPU_INDEX=0
	for DEVICE in $GPU_DEVICES; do
		# Get device number
		DEVICE_NUM=$(echo $DEVICE | sed 's/\/dev\/nvidia//')

		# Skip non-numeric devices
		if ! [[ "$DEVICE_NUM" =~ ^[0-9]+$ ]]; then
			continue
		fi

		# Create GPU mapping
		echo "NodeName=$HOSTNAME Name=gpu File=$DEVICE" >>$TEMP_GRES_CONF
		GPU_INDEX=$((GPU_INDEX + 1))
	done

	# If no mappings were created, add a generic mapping
	if [ "$GPU_INDEX" -eq 0 ]; then
		echo "NodeName=$HOSTNAME Name=gpu Count=$GPU_COUNT" >>$TEMP_GRES_CONF
	fi

	# Move temporary file to actual location
	mv $TEMP_GRES_CONF /etc/slurm/gres.conf

	log "gres.conf configuration generated:"
	cat /etc/slurm/gres.conf
}

# Update slurm.conf to include GresTypes
update_slurm_conf() {
	log "Updating slurm.conf to support GPU resources..."

	# Check if slurm.conf already contains GresTypes
	if grep -q "GresTypes" /etc/slurm/slurm.conf; then
		log "slurm.conf already contains GresTypes settings, not modifying"
	else
		# Add GresTypes setting
		echo "GresTypes=gpu" >>/etc/slurm/slurm.conf
		log "Added GresTypes=gpu to slurm.conf"
	fi

	# sed -i "s/<<HOSTNAME>>/$(hostname)/" /etc/slurm/slurm.conf
	sed -i "s/<<CPU>>/$(nproc)/" /etc/slurm/slurm.conf
	sed -i "s/<<MEMORY>>/$(if [[ "$(slurmd -C)" =~ RealMemory=([0-9]+) ]]; then echo "${BASH_REMATCH[1]}"; else exit 100; fi)/" /etc/slurm/slurm.conf
}

# Start Slurm services
start_slurm_services() {
	log "Starting Slurm services..."

	# Start munge service
	log "Starting munge service..."
	service munge start

	log "Starting mysql service..."
	service mysql start

	mysql <<EOF
	create user 'jc'@'localhost' identified by 'jc@1234';
	create database slurm_acct_db;
	grant all PRIVILEGES on slurm_acct_db.* TO 'jc'@'localhost' with grant option;
EOF

	# Start Slurm database service
	log "Starting slurmdbd service..."
	service slurmdbd start

	# Start Slurm controller service
	log "Starting slurmctld service..."
	sleep 3
	service slurmctld start

	# Start Slurm node service
	log "Starting slurmd service..."
	service slurmd start

}

# Start SSH service
start_ssh_service() {
	log "Starting SSH service..."
	service ssh start
}

# Main function
main() {
	log "Initializing Docker container..."
	echo "10.251.102.1 mirrors.shanhe.com" >>/etc/hosts

	# Detect GPUs
	detect_gpus

	# Generate gres.conf configuration
	generate_gres_conf

	# Update slurm.conf
	update_slurm_conf

	# Start SSH service
	start_ssh_service

	# Start Slurm services
	start_slurm_services

	log "Initialization complete, container is ready"
}

# Execute main function
main "$@"
