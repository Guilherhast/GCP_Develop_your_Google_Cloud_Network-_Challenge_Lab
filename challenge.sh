#!/bin/bash
## tips
# gcloud compute instances list
# gcloud compute firewall-rules list
# gcloud compute ssh INSTANCE_NAME --tunnel-through-iap


CLOUDCMD=echo
KUBECMD=echo
#KUBECMD=kubectl

RESETCOLOR='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'

DELAY=0

## Defining constants

### Project wide
PROJECT=123

ZONE=us-central1-f
REGION=${ZONE%-*}


ADMINEMAIL=admin@gmail.com

### Development network

DEVNETNAME=griffin-dev-vpc

DEVNETSUBNET1NAME=griffin-dev-wp
DEVNETSUBNET1RANGE=192.168.16.0/20

DEVNETSUBNET2NAME=griffin-dev-mgmt
DEVNETSUBNET2RANGE=192.168.32.0/20


### Production network

PRODNETNAME=griffin-prod-vpc

PRODNETSUBNET1NAME=griffin-prod-wp
PRODNETSUBNET1RANGE=192.168.48.0/20

PRODNETSUBNET2NAME=griffin-prod-mgmt
PRODNETSUBNET2RANGE=192.168.64.0/20


## Bastian

BASTIONISNTANCENAME=bastion
BASTIONNETWORKTAGS=bastion-server
BASTIANINSTANCETYPE=e2-micro

WEBSERVERISNTANCENAME=webserver
WEBSERVERNETWORKTAGS=web-server

## Sql

SQLNAME=griffin-dev-db
SQLVERSION=MYSQL_8_0
SQLROOTPASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

KBNENVFILE=./wp-k8s/wp-env.yaml
KBNDEPLOYFILE=./wp-k8s/wp-deployment.yaml
KBNSERVICEFILE=./wp-k8s/wp-service.yaml

SQLUSERNAME=wp_user
SQLUSERPASSWORD=stormwind_rules
#SQLUSERPASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

SQLQUERY="
CREATE DATABASE wordpress;
CREATE USER \"${SQLUSERNAME}\"@\"%\" IDENTIFIED BY \"${SQLUSERPASSWORD}\";
GRANT ALL PRIVILEGES ON wordpress.* TO \"${SQLUSERNAME}\"@\"%\";
FLUSH PRIVILEGES;
" # I would rather use a random password

## Kubernetes

CLUSTERNAME=griffin-dev
CLUSTERSUBNET=$DEVNETSUBNET1NAME
CLUSTERNUMNODES=2

## Health check
HEALTHCHECKNAME=health-check

## Access
ENGINEEREMAIL=engineer@gmail.com

## Function definitions
function setUpProject(){
	$CLOUDCMD config set project $PROJECT
	$CLOUDCMD config set compute/region $REGION
	$CLOUDCMD config set compute/zone $ZONE
}

function createDevelopmentNetwork(){
	$CLOUDCMD compute networks create $DEVNETNAME \
		--subnet-mode=custom &&

	$CLOUDCMD compute networks subnets create $DEVNETSUBNET1NAME \
		--network=$DEVNETNAME \
		--range=$DEVNETSUBNET1RANGE &&

	$CLOUDCMD compute networks subnets create $DEVNETSUBNET2NAME \
		--network=$DEVNETNAME \
		--range=$DEVNETSUBNET2RANGE
}

function createProductionNetwork(){
	$CLOUDCMD compute networks create $PRODNETNAME \
		--subnet-mode=custom &&

	$CLOUDCMD compute networks subnets create $PRODNETSUBNET1NAME \
		--network=$PRODNETNAME \
		--range=$PRODNETSUBNET1RANGE &&

	$CLOUDCMD compute networks subnets create $PRODNETSUBNET2NAME \
		--network=$PRODNETNAME \
		--range=$PRODNETSUBNET2RANGE
}

function createBastianInstance(){

	$CLOUDCMD compute instances create instance-name \
		--machine-type $BASTIANINSTANCETYPE \
		--network-interface $PRODNETNAME \
		--network-interface $DEVNETNAME

}

function createSqlInstance(){

	$CLOUDCMD sql instances create $SQLNAME \
		--database-version=$SQLVERSION \
		--root-password=$SQLROOTPASSWORD \
		--high-availability-tier=REGIONAL &&

	export SQLROOTPASSWORD=$SQLROOTPASSWORD
	echo -e Root password: "${ORANGE}$SQLROOTPASSWORD${RESETCOLOR}"

	#ln -s ./wp-k8s $HOME/wp-k8s  &&


	$CLOUDCMD sql connect "${SQLNAME}" --user=root \
	--quiet <<EOF
	${SQLQUERY}
EOF

}

function editKubernetesFiles(){
	sed -i "18c\ \ username: ${SQLUSERNAME}" $KBNENVFILE &&
	sed -i "19c\ \ password: ${SQLUSERPASSWORD}" $KBNENVFILE &&
	sed -i "42c\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \"-instances=$SQLNAME=tcp:3306\"" $KBNDEPLOYFILE
}

function createKubernetesCluster(){
	$CLOUDCMD container clusters create $CLUSTERNAME \
		--num-nodes=$CLUSTERNUMNODES &&

	$CLOUDCMD iam service-accounts keys create key.json \
		--iam-account=cloud-sql-proxy@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com &&

	$KUBECMD create secret generic cloudsql-instance-credentials \
		--from-file key.json
}
function createKubernetesDeployments(){
	$KUBECMD create -f $KBNDEPLOYFILE
}
function createKubernetesServive(){
	$KUBECMD create -f $KBNSERVICEFILE
}

function kubernetesGetUrls(){
	URL=$($KUBECMD get svc \
		-o=jsonpath="{.status.loadBalancer.ingress[0].ip}")
	echo -e "URL: ${BLUE}$URL${RESETCOLOR}" 
}

function createUptimeCheck(){
	URL=$($KUBECMD get svc \
		-o=jsonpath="{.status.loadBalancer.ingress[0].ip}") &&


	$CLOUDCMD monitoring uptime create $HEALTHCHECKNAME \
		--http-path / \
		--resource-type uptime-url \
		--resource-labels=host=$URL,project_id=$PROJECT \
		--check-interval 60s \
		--timeout 10s \
		--host $URL

}

function grantAccess(){
	$CLOUDCMD projects add-iam-policy-binding $PROJECT \
    --member=user:$ENGINEEREMAIL \
    --role=roles/editor

}

## General functions

echoDivision(){
	echo
	echo -e "${GREEN}$*${RESETCOLOR}"
	echo
}
# Run
#
echoDivision "Starting script" &&
echoDivision "Setting up project" &&
setUpProject &&
echoDivision "Creating Networks" &&
echoDivision "Development" &&
createDevelopmentNetwork &&
echoDivision "Production" &&
createProductionNetwork &&
echoDivision "Create instance" &&
createBastianInstance &&
echoDivision "Create sql" &&
createSqlInstance &&
echoDivision "Editing files" &&
editKubernetesFiles &&
echoDivision "Create kubernetes cluster" &&
createKubernetesCluster &&
echoDivision "Create kubernetes deployment" &&
createKubernetesDeployments &&
echoDivision "Create kubernetes service" &&
createKubernetesServive &&
echoDivision "Sleeping" &&
sleep $DELAY
echoDivision "Getting urls" &&
kubernetesGetUrls &&
echoDivision "Getting urls" &&
createUptimeCheck &&
echoDivision "Grantting access" &&
grantAccess &&
echoDivision "Done! Have a nice day."
