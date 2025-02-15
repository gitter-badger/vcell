#!/usr/bin/env bash

shopt -s -o nounset

#----------------------------------------
# command-line options
#----------------------------------------
skip_install4j=false
skip_build=false
skip_extra_solvers=false
restart=false
mvn_repo=$HOME/.m2

show_help() {
	echo "usage: deploy.sh [OPTIONS] config_file build_number"
	echo "  ARGUMENTS"
	echo "    config_file           config file for deployment (with bash syntax)"
	echo "    build_number          vcell build number (e.g. build 55 gives VCell_6.2_Alpha_55)"
	echo "  [OPTIONS]"
	echo "    -h | --help           show this message"
	echo "    --restart             restart vcell after deploy"
	echo "    --mvn-repo REPO_DIR   override local maven repository (defaults to $HOME/.m2)"
	echo "    --skip-build          (debugging) skip full maven clean build"
	echo "    --skip-install4j      (debugging) skip installer generation"
	echo "    --skip-extra-solvers  (TEMPORARY) skip installing 'extra' server-side solvers from"
	echo "                          <install-dir>/localsolvers/extra-solvers.tgz (e.g. Chombo, PETSc)"
	exit 1
}

if [ "$#" -lt 2 ]; then
    show_help
fi

while :; do
	case $1 in
		-h|--help)
			show_help
			exit
			;;
		--restart)
			restart=true
			;;
		--mvn-repo)
			shift
			mvn_repo=$1
			;;
		--skip-build)
			skip_build=true
			;;
		--skip-extra-solvers)
			skip_build=true
			;;
		--skip-install4j)
			skip_install4j=true
			;;
		-?*)
			printf 'ERROR: Unknown option: %s\n' "$1" >&2
			echo ""
			show_help
			;;
		*)               # Default case: No more options, so break out of the loop.
			break
	esac
	shift
done

if [ "$#" -ne 2 ]; then
    show_help
fi

includefile=$1
. $includefile $2
rc=$?
if [ "$rc" -ne 0 ]; then
	echo "failed to run configuration file $includefile"
	exit 1
fi

. $vcell_secretsDir/deploySecrets.include

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "deploy directory is ${DIR}"

projectRootDir=`dirname $DIR`
echo "project root directory is ${projectRootDir}"
projectTargetDir=$projectRootDir/target

serverTargetDir=$projectRootDir/vcell-server/target

# oracle dependencies
oracleTargetDir=$projectRootDir/vcell-oracle/target
ucpJarFilePath=$projectRootDir/ucp/src/ucp.jar
ojdbc6JarFilePath=$projectRootDir/ojdbc6/src/ojdbc6.jar

apiTargetDir=$projectRootDir/vcell-api/target
apiDocrootDir=$projectRootDir/vcell-api/docroot
apiWebappDir=$projectRootDir/vcell-api/webapp

adminTargetDir=$projectRootDir/vcell-admin/target
adminJarsDir=$adminTargetDir/maven-jars

clientTargetDir=$projectRootDir/vcell-client/target
clientJarsDir=$clientTargetDir/maven-jars

#--------------------------------------------------------------------------
# build project, generate user help files, gather jar files
# 1) remove previously generated vcellDocs
# 2) maven build and copy dependent jars from maven repo (maven clean install dependency:copy-dependencies)
#---------------------------------------------------------------------------
if [ "$skip_build" = false ]; then
	cd $projectRootDir
	echo "removing old docs from resources, will be rebuilt by exec plugin (DocumentCompiler)"
	rm -r $projectRootDir/vcell-client/src/main/resources/vcellDocs
	echo "build vcell"
	mvn -Dmaven.repo.local=$mvn_repo clean install dependency:copy-dependencies
	if [ $? -ne 0 ]; then
		echo "failed maven build: mvn -Dmaven.repo.local=$mvn_repo clean install dependency:copy-dependencies"
		exit -1
	fi
fi

deployRootDir=$DIR

deployInstall4jDir=$deployRootDir/client/install4j

isMac=false
if [[ "$OSTYPE" == "darwin"* ]]; then
	isMac=true
fi


if [[ "$vcell_server_os" = "mac64" ]]; then
	localsolversDir=localsolvers/mac64
	nativelibsDir=nativelibs/mac64
elif [[ "$vcell_server_os" = "linux64" ]]; then
	localsolversDir=localsolvers/linux64
	nativelibsDir=nativelibs/linux64
else
	echo "vcell server os specied as $vcell_server_os expecting either 'linux64' or 'macos'"
	exit -1
fi

#
# 
#
stagingRootDir=$projectTargetDir/server-staging/
stagingConfigsDir=$stagingRootDir/configs
stagingJarsDir=$stagingRootDir/jars
stagingPythonScriptsDir=$stagingRootDir/pythonScripts
stagingNativelibsDir=$stagingRootDir/$nativelibsDir
stagingInstallersDir=$projectRootDir/target/installers

projectSolversDir=$projectRootDir/$localsolversDir

jms_queue_simReq="simReq${vcell_site_camel}"
jms_queue_dataReq="simDataReq${vcell_site_camel}"
jms_queue_dbReq="dbReq${vcell_site_camel}"
jms_queue_simJob="simJob${vcell_site_camel}"
jms_queue_workerEvent="workerEvent${vcell_site_camel}"
jms_topic_serviceControl="serviceControl${vcell_site_camel}"
jms_topic_daemonControl="daemonControl${vcell_site_camel}"
jms_topic_clientStatus="clientStatus${vcell_site_camel}"
jms_datadir="${vcell_server_sitedir}/activemq/data"
jms_logdir="${vcell_server_sitedir}/activemq/log"
jms_container_name="activemq${vcell_site_camel}"
jms_host="${vcell_jms_host}"
jms_port="${vcell_jms_port}"
jms_webport="${vcell_jms_webport}"
jms_user="${vcell_jms_user}"

mongodb_containername="mongo${vcell_site_camel}"
mongodb_host="${vcell_mongodb_host}"
mongodb_port="${vcell_mongodb_port}"

installed_server_sitedir=$vcell_server_sitedir
installedConfigsDir=$installed_server_sitedir/configs
installedJarsDir=$installed_server_sitedir/jars
installedNativelibsDir=$installed_server_sitedir/$nativelibsDir
installedPythonScriptsDir=$installed_server_sitedir/pythonScripts
installedSolversDir=$installed_server_sitedir/$localsolversDir
installedTmpDir=$installed_server_sitedir/tmp
installedLogDir=$installed_server_sitedir/log
installedJmsBlobFilesDir=$installed_server_sitedir/blobFiles
installedHtclogsDir=$installed_server_sitedir/htclogs
installedJavaprefsDir=$installed_server_sitedir/javaprefs
installedSystemPrefsDir=$installed_server_sitedir/javaprefs/.systemPrefs
installedInstallersDir=$installed_server_sitedir/installers
installedPrimarydataDir=$vcell_primary_datadir
installedSecondarydataDir=$vcell_secondary_datadir
installedParalleldataDir=$vcell_parallel_datadir
installedExportDir=$vcell_export_dir
installedExportUrl=$vcell_export_url
installedMpichHomedir=$vcell_mpich_homedir
installedDocrootDir=$installed_server_sitedir/docroot
installedWebappDir=$installed_server_sitedir/webapp
installedJmsDataDir=$installed_server_sitedir/jmsdata
installedJmsLogDir=$installed_server_sitedir/jmslog

pathto_server_sitedir=$vcell_pathto_sitedir
pathto_ConfigsDir=$pathto_server_sitedir/configs
pathto_JarsDir=$pathto_server_sitedir/jars
pathto_NativelibsDir=$pathto_server_sitedir/$nativelibsDir
pathto_PythonScriptsDir=$pathto_server_sitedir/pythonScripts
pathto_SolversDir=$pathto_server_sitedir/$localsolversDir
pathto_TmpDir=$pathto_server_sitedir/tmp
pathto_LogDir=$pathto_server_sitedir/log
pathto_JmsBlobFilesDir=$pathto_server_sitedir/blobFiles
pathto_HtclogsDir=$pathto_server_sitedir/htclogs
pathto_JavaprefsDir=$pathto_server_sitedir/javaprefs
pathto_SystemPrefsDir=$pathto_server_sitedir/javaprefs/.systemPrefs
pathto_InstallersDir=$pathto_server_sitedir/installers
pathto_DocrootDir=$pathto_server_sitedir/docroot
pathto_WebappDir=$pathto_server_sitedir/webapp
pathto_JmsDataDir=$pathto_server_sitedir/jmsdata
pathto_JmsLogDir=$pathto_server_sitedir/jmslog
#pathto_PrimarydataDir=$vcell_primary_datadir
#pathto_SecondarydataDir=$vcell_secondary_datadir
#pathto_ParalleldataDir=$vcell_parallel_datadir
#pathto_ExportDir=$vcell_export_dir
#pathto_ExportUrl=$vcell_export_url
#pathto_MpichHomedir=$vcell_mpich_homedir


installedVisitExe=/share/apps/vcell2/visit/visit2.9/visit2_9_0.linux-x86_64/bin/visit
installedPython=/share/apps/vcell2/vtk/usr/bin/vcellvtkpython

#--------------------------------------------------------------
# gather jar files using maven dependency plugin
#--------------------------------------------------------------
cd $projectRootDir
echo "populate maven-jars"
mvn -Dmaven.repo.local=$mvn_repo dependency:copy-dependencies
if [ $? -ne 0 ]; then
	echo "failed: mvn -Dmaven.repo.local=$mvn_repo dependency:copy-dependencies"
	exit -1
fi

# bring in vcell-client.jar
cp $clientTargetDir/*.jar ${clientJarsDir}
# gather classpath (filenames only), Install4J will add the correct separator
vcellClasspathColonSep=`ls -m ${clientJarsDir} | tr -d '[:space:]' | tr ',' ':'`

#---------------------------------------------------------------
# build install4j platform specific installers for VCell client
# 
# cd to install4j directory which contains the Vagrant box 
# definition and scripts for building install4J installers 
# for VCell client.
#
# installers are installed in project/target/installers directory
#---------------------------------------------------------------
install4jWorkingDir=$projectRootDir/target/install4j-working
install4jDeploySettings=$install4jWorkingDir/DeploySettings.include

I4J_pathto_Install4jWorkingDir=$vcell_I4J_pathto_mavenRootDir/target/install4j-working
I4J_pathto_Install4jDeploySettings=$I4J_pathto_Install4jWorkingDir/DeploySettings.include

mkdir -p $install4jWorkingDir
if [ -e $install4jDeploySettings ]; then
	rm $install4jDeploySettings
fi
touch $install4jDeploySettings

echo "i4j_pathto_install4jc=$vcell_I4J_pathto_install4jc"			>> $install4jDeploySettings
echo "compiler_updateSiteBaseUrl=$vcell_I4J_updateSiteBaseUrl"		>> $install4jDeploySettings
echo "compiler_vcellIcnsFile=$vcell_I4J_pathto_vcellIcnsFile"		>> $install4jDeploySettings
echo "compiler_mavenRootDir=$vcell_I4J_pathto_mavenRootDir"			>> $install4jDeploySettings
echo "compiler_softwareVersionString=$vcell_softwareVersionString"	>> $install4jDeploySettings
echo "compiler_Site=$vcell_site_camel"								>> $install4jDeploySettings
echo "compiler_vcellVersion=$vcell_version"							>> $install4jDeploySettings
echo "compiler_vcellBuild=$vcell_build"								>> $install4jDeploySettings
echo "compiler_rmiHosts=$vcell_rmihosts"							>> $install4jDeploySettings
echo "compiler_bioformatsJarFile=$vcell_bioformatsJarFile"			>> $install4jDeploySettings
echo "compiler_bioformatsJarDownloadURL=$vcell_bioformatsJarDownloadURL" >> $install4jDeploySettings
echo "compiler_applicationId=$vcell_applicationId"					>> $install4jDeploySettings
echo "i4j_pathto_jreDir=$vcell_I4J_pathto_jreDir"					>> $install4jDeploySettings
echo "i4j_pathto_secretsDir=$vcell_I4J_pathto_secretsDir"			>> $install4jDeploySettings
echo "install_jres_into_user_home=$vcell_I4J_install_jres_into_user_home"	>> $install4jDeploySettings
echo "i4j_pathto_install4JFile=$vcell_I4J_pathto_installerFile"		>> $install4jDeploySettings
echo "i4j_pathto_mavenRootDir=$vcell_I4J_pathto_mavenRootDir"		>> $install4jDeploySettings
echo "compiler_vcellClasspathColonSep=$vcellClasspathColonSep"	>> $install4jDeploySettings

if [ "$skip_install4j" = false ]; then
	cd $deployInstall4jDir
	if [ "$vcell_I4J_use_vagrant" = true ]; then
	
		if [ "$vcell_I4J_install_jres_into_user_home" = true ] && [ ! -d $vcell_I4J_jreDir ]; then
			echo "expecting to find directory $vcell_I4J_jreDir with downloaded JREs compatible with Install4J configuration"
			exit -1
		fi
		
		echo "starting Vagrant box to run Install4J to target all platforms"
		vagrant up
		
		echo "invoking script on vagrant box to build installers"
		vagrant ssh -c "/vagrant/build_installers.sh $I4J_pathto_Install4jDeploySettings"
		i4j_retcode=$?
		
		echo "shutting down vagrant"
		vagrant halt
	else
		$DIR/client/install4j/build_installers.sh $install4jDeploySettings
		i4j_retcode=$?
	fi
	
	if [ $i4j_retcode -eq 0 ]; then
		echo "client-installers built"
	else
		echo "client-installer build failed"
		exit -1;
	fi
	
	echo "client install4j installers located in $stagingInstallersDir"
fi

cd $DIR

#-------------------------------------------------------
# build server-staging area
#-------------------------------------------------------
#
# build stagingDir/configs
#
mkdir -p $stagingRootDir
mkdir -p $stagingConfigsDir
mkdir -p $stagingJarsDir
mkdir -p $stagingPythonScriptsDir
mkdir -p $stagingNativelibsDir

cp -p $adminTargetDir/maven-jars/*.jar $stagingJarsDir
cp -p $adminTargetDir/$vcell_vcellAdminJarFileName $stagingJarsDir
cp -p $apiTargetDir/maven-jars/*.jar $stagingJarsDir
cp -p $apiTargetDir/$vcell_vcellApiJarFileName $stagingJarsDir

cp -p $oracleTargetDir/maven-jars/*.jar $stagingJarsDir
cp -p $oracleTargetDir/$vcell_vcellOracleJarFileName $stagingJarsDir
cp -p $ucpJarFilePath $stagingJarsDir
cp -p $ojdbc6JarFilePath $stagingJarsDir

cp -p $serverTargetDir/maven-jars/*.jar $stagingJarsDir
cp -p $serverTargetDir/$vcell_vcellServerJarFileName $stagingJarsDir
cp -p $projectRootDir/$nativelibsDir/* $stagingNativelibsDir
cp -p -R $projectRootDir/pythonScripts/* $stagingPythonScriptsDir

#
# build stagingDir/configs
#
cp -p $includefile $stagingConfigsDir
cp -p server/deployInfo/* $stagingConfigsDir


function sed_in_place() { if [ "$isMac" = true ]; then sed -i "" "$@"; else sed -i "$@"; fi }

#
# substitute values within vcell.include template from 
# 
stagingVCellInclude=$stagingConfigsDir/vcell.include
sed_in_place "s/GENERATED-SITE/$vcell_site_lower/g"						$stagingVCellInclude
sed_in_place "s/GENERATED-RMIHOST/$vcell_rmihost/g"						$stagingVCellInclude
sed_in_place "s/GENERATED-RMIPORT-LOW/$vcell_rmiport_low/g"				$stagingVCellInclude
sed_in_place "s/GENERATED-RMIPORT-HIGH/$vcell_rmiport_high/g"				$stagingVCellInclude
sed_in_place "s/GENERATED-VCELLSERVICE-JMXPORT/$vcell_vcellservice_jmxport/g"	$stagingVCellInclude
sed_in_place "s/GENERATED-RMISERVICEHIGH-JMXPORT/$vcell_rmiservice_high_jmxport/g"	$stagingVCellInclude
sed_in_place "s/GENERATED-RMISERVICEHTTP-JMXPORT/$vcell_rmiservice_http_jmxport/g"	$stagingVCellInclude
sed_in_place "s/GENERATED-SERVICEHOST/$vcell_servicehost/g"				$stagingVCellInclude
sed_in_place "s/GENERATED-NAGIOSPW/nagcmd/g" 								$stagingVCellInclude
sed_in_place "s/GENERATED-MONITOR-PORT/${vcell_monitor_queryport}/g"		$stagingVCellInclude
sed_in_place "s/GENERATED-JVMDEF/test.monitor.port/g"						$stagingVCellInclude
sed_in_place "s+GENERATED-COMMON-JRE+$vcell_common_jre+g"					$stagingVCellInclude
sed_in_place "s+GENERATED-RMISERVICE-JRE+$vcell_common_jre_rmi+g"			$stagingVCellInclude
sed_in_place "s+GENERATED-NATIVELIBSDIR+$installedNativelibsDir+g"			$stagingVCellInclude
sed_in_place "s+GENERATED-JARSDIR+$installedJarsDir+g"						$stagingVCellInclude
sed_in_place "s+GENERATED-LOGDIR+$installedLogDir+g"						$stagingVCellInclude
sed_in_place "s+GENERATED-CONFIGSDIR+$installedConfigsDir+g"				$stagingVCellInclude
sed_in_place "s+GENERATED-TMPDIR+$installedTmpDir+g"						$stagingVCellInclude
sed_in_place "s+GENERATED-JAVAPREFSDIR+$installedJavaprefsDir+g"			$stagingVCellInclude
sed_in_place "s+GENERATED-JARS+$installedJarsDir/*+g"						$stagingVCellInclude
sed_in_place "s+GENERATED-API-ROOTDIR+$installed_server_sitedir+g"			$stagingVCellInclude
sed_in_place "s+GENERATED-APIKEYSTORE-PATH+$vcell_secrets_tlsKeystore_path+g"	$stagingVCellInclude
sed_in_place "s/GENERATED-APIKEYSTORE-PSWD/$vcell_secrets_tlsKeystore_pswd/g"	$stagingVCellInclude
sed_in_place "s/GENERATED-APIHOST/$vcell_apihost/g"							$stagingVCellInclude
sed_in_place "s/GENERATED-APIPORT/$vcell_apiport/g"							$stagingVCellInclude
sed_in_place "s/GENERATED-VCELLUSER/$vcell_user/g"							$stagingVCellInclude
sed_in_place "s/GENERATED-JMSQUEUE-SIMREQ/${jms_queue_simReq}/g"				$stagingVCellInclude
sed_in_place "s/GENERATED-JMSQUEUE-DATAREQ/${jms_queue_dataReq}/g"			$stagingVCellInclude
sed_in_place "s/GENERATED-JMSQUEUE-DBREQ/${jms_queue_dbReq}/g"				$stagingVCellInclude
sed_in_place "s/GENERATED-JMSQUEUE-SIMJOB/${jms_queue_simJob}/g"				$stagingVCellInclude
sed_in_place "s/GENERATED-JMSQUEUE-WORKEREVENT/${jms_queue_workerEvent}/g"		$stagingVCellInclude
sed_in_place "s/GENERATED-JMSTOPIC-SERVICECONTROL/${jms_topic_serviceControl}/g"	$stagingVCellInclude
sed_in_place "s/GENERATED-JMSTOPIC-DAEMONCONTROL/${jms_topic_daemonControl}/g"	$stagingVCellInclude
sed_in_place "s/GENERATED-JMSTOPIC-CLIENTSTATUS/${jms_topic_clientStatus}/g"	$stagingVCellInclude
sed_in_place "s+GENERATED-JMSURL+${vcell_jms_url}+g"							$stagingVCellInclude
sed_in_place "s/GENERATED-JMSUSER/${vcell_jms_user}/g"						$stagingVCellInclude
sed_in_place "s/GENERATED-JMSPSWD/${vcell_secrets_jms_pswd}/g"				$stagingVCellInclude
sed_in_place "s/GENERATED-JMSHOST/${vcell_jms_host}/g"						$stagingVCellInclude
sed_in_place "s/GENERATED-JMSPORT/${vcell_jms_port}/g"						$stagingVCellInclude
sed_in_place "s/GENERATED-JMSWEBPORT/${vcell_jms_webport}/g"					$stagingVCellInclude
sed_in_place "s/GENERATED-JMSCONTAINERNAME/${jms_container_name}/g"			$stagingVCellInclude
sed_in_place "s+GENERATED-JMSDATADIR+${jms_datadir}+g"						$stagingVCellInclude
sed_in_place "s+GENERATED-JMSLOGDIR+${jms_logdir}+g"							$stagingVCellInclude
sed_in_place "s/GENERATED-MONGODB-HOST/${mongodb_host}/g"						$stagingVCellInclude
sed_in_place "s/GENERATED-MONGODB-PORT/${mongodb_port}/g"						$stagingVCellInclude
sed_in_place "s/GENERATED-MONGODB-CONTAINERNAME/${mongodb_containername}/g"	$stagingVCellInclude

sed_in_place "s/GENERATED-HTC-USESSH/$vcell_htc_usessh/g"					$stagingVCellInclude
if [ "$vcell_htc_usessh" = true ]; then
	sed_in_place "s/GENERATED-HTC-SSH-HOST/$vcell_htc_sshhost/g"			$stagingVCellInclude
	sed_in_place "s/GENERATED-HTC-SSH-USER/$vcell_htc_sshuser/g"			$stagingVCellInclude
	sed_in_place "s+GENERATED-HTC-SSH-DSAKEYFILE+$vcell_htc_sshDsaKeyFile+g"	$stagingVCellInclude
else
	sed_in_place "s/GENERATED-HTC-SSH-HOST/NOT-DEFINED/g"					$stagingVCellInclude
	sed_in_place "s/GENERATED-HTC-SSH-USER/NOT-DEFINED/g"					$stagingVCellInclude
	sed_in_place "s/GENERATED-HTC-SSH-DSAKEYFILE/NOT-DEFINED/g"			$stagingVCellInclude
fi

if grep -Fq "GENERATED" $stagingVCellInclude
then
    echo "failed to replace all GENERATED tokens in $stagingVCellInclude"
    grep "GENERATED" $stagingVCellInclude
    exit -1
fi

#
# build generated vcell64.properties file - VCell System properties read by PropertyLoader
#
propfile=$stagingConfigsDir/vcell64.properties
if [ -e $propfile ]; then
	rm $propfile
fi
touch $propfile

echo "vcell.server.id = $vcell_site_upper" 									>> $propfile
echo "vcell.softwareVersion = $vcell_softwareVersionString" 				>> $propfile
echo "vcell.installDir = $installed_server_sitedir" 						>> $propfile
echo "vcell.python.executable = $vcell_python_executable"					>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "#JMS Info"															>> $propfile
echo "#"																	>> $propfile
echo "vcell.jms.provider = ActiveMQ"										>> $propfile
echo "vcell.jms.url = $vcell_jms_url" 										>> $propfile
echo "vcell.jms.user = $vcell_jms_user"										>> $propfile
echo "vcell.jms.password = $vcell_secrets_jms_pswd"							>> $propfile
echo "vcell.jms.queue.simReq = $jms_queue_simReq"						>> $propfile
echo "vcell.jms.queue.dataReq = $jms_queue_dataReq"				>> $propfile
echo "vcell.jms.queue.dbReq = $jms_queue_dbReq"						>> $propfile
echo "vcell.jms.queue.simJob = $jms_queue_simJob"						>> $propfile
echo "vcell.jms.queue.workerEvent = $jms_queue_workerEvent"			>> $propfile
echo "vcell.jms.topic.serviceControl = $jms_topic_serviceControl"		>> $propfile
echo "vcell.jms.topic.daemonControl = $jms_topic_daemonControl"		>> $propfile
echo "vcell.jms.topic.clientStatus = $jms_topic_clientStatus"			>> $propfile
echo "vcell.jms.blobMessageMinSize = 100000"								>> $propfile
echo "vcell.jms.blobMessageTempDir = $installedJmsBlobFilesDir"				>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "#Oracle Database Info"												>> $propfile
echo "#"																	>> $propfile
echo "vcell.server.dbConnectURL = $vcell_database_url"						>> $propfile
echo "vcell.server.dbDriverName = $vcell_database_driver"					>> $propfile
echo "vcell.server.dbUserid = $vcell_database_user"							>> $propfile
echo "vcell.server.dbPassword = $vcell_secrets_database_pswd"				>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "#Amplistor Info"														>> $propfile
echo "#"																	>> $propfile
echo "vcell.amplistor.vcellserviceurl = $vcell_amplistor_url"				>> $propfile
echo "vcell.amplistor.vcellservice.user = $vcell_amplistor_user"			>> $propfile
echo "vcell.amplistor.vcellservice.password = $vcell_secrets_amplistor_pswd"	>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "#Mongo Info"															>> $propfile
echo "#"																	>> $propfile
echo "vcell.mongodb.host = $vcell_mongodb_host"								>> $propfile
echo "vcell.mongodb.port = $vcell_mongodb_port"								>> $propfile
echo "vcell.mongodb.database = $vcell_mongodb_database"						>> $propfile
echo "vcell.mongodb.loggingCollection = $vcell_mongodb_collection"			>> $propfile
echo "vcell.mongodb.threadSleepMS = 10000"									>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "#Mail Server Info (lost password func)"								>> $propfile
echo "#"																	>> $propfile
echo "vcell.smtp.hostName = $vcell_smtp_host"								>> $propfile
echo "vcell.smtp.port = $vcell_smtp_port"									>> $propfile
echo "vcell.smtp.emailAddress = $vcell_smtp_email"							>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "#Visit Info"															>> $propfile
echo "#"																	>> $propfile
echo "vcell.visit.smoldynscript = $installedConfigsDir/convertSmoldyn.py"	>> $propfile
echo "vcell.visit.smoldynvisitexecutable = $installedVisitExe"				>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# java simulation executable"											>> $propfile
echo "#"																	>> $propfile
echo "vcell.javaSimulation.executable = $installedConfigsDir/JavaSimExe64"	>> $propfile
echo "vcell.simulation.preprocessor = $installedConfigsDir/JavaPreprocessor64"	>> $propfile
echo "vcell.simulation.postprocessor = $installedConfigsDir/JavaPostprocessor64"	>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# Server configuration"												>> $propfile
echo "#"																	>> $propfile
echo "vcell.primarySimdatadir = $installedPrimarydataDir"					>> $propfile
echo "vcell.secondarySimdatadir = $installedSecondarydataDir"				>> $propfile
echo "vcell.parallelDatadir = $installedParalleldataDir"					>> $propfile
echo "vcell.databaseThreads = 5"											>> $propfile
echo "vcell.exportdataThreads = 3"											>> $propfile
echo "vcell.simdataThreads = 5"												>> $propfile
echo "vcell.htcworkerThreads = 10"											>> $propfile
echo "vcell.export.baseURL = $installedExportUrl"							>> $propfile
echo "vcell.export.baseDir = $installedExportDir/"							>> $propfile
echo "vcell.databaseCacheSize = 50000000"									>> $propfile
echo "vcell.simdataCacheSize = 200000000"									>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# Limits"																>> $propfile
echo "#"																	>> $propfile
echo "vcell.limit.jobMemoryMB = 20000"										>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# Quota info"															>> $propfile
echo "#"																	>> $propfile
echo "vcell.server.maxOdeJobsPerUser = 20"									>> $propfile
echo "vcell.server.maxPdeJobsPerUser = 20"									>> $propfile
echo "vcell.server.maxJobsPerScan = 100"									>> $propfile
echo "vcell.server.maxJobsPerSite = 300"									>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# HTC info"															>> $propfile
echo "#"																	>> $propfile
echo "vcell.htc.logdir = $installedHtclogsDir/"								>> $propfile
echo "vcell.htc.jobMemoryOverheadMB = 70"									>> $propfile
echo "vcell.htc.user = vcell"												>> $propfile
echo "vcell.htc.queue ="													>> $propfile
echo "#vcell.htc.pbs.home ="												>> $propfile
echo "#vcell.htc.sge.home ="												>> $propfile
echo "#vcell.htc.sgeModulePath ="											>> $propfile
echo "#vcell.htc.pbsModulePath ="											>> $propfile
echo "vcell.htc.mpi.home = $vcell_mpich_homedir/"							>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# uncomment to specify which PBS or SGE submission queue to use."		>> $propfile
echo "# when not specified, the default queue is used."						>> $propfile
echo "#vcell.htc.queue = myQueueName"										>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# uncomment to change the Simulation Job Timeout."					>> $propfile
echo "# useful if restart takes a long time, units are in milliseconds"		>> $propfile
echo "#"																	>> $propfile
echo "# here 600000 = 60 * 1000 * 10 = 10 minutes"							>> $propfile
echo "# the default hard-coded in "											>> $propfile
echo "# MessageConstants.INTERVAL_SIMULATIONJOBSTATUS_TIMEOUT_MS"			>> $propfile
echo "#"																	>> $propfile
echo "# vcell.htc.htcSimulationJobStatusTimeout=600000"						>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# Client Timeout in milliseconds"										>> $propfile
echo "#"																	>> $propfile
echo "vcell.client.timeoutMS = 600000"										>> $propfile
echo " "																	>> $propfile
echo "#"																	>> $propfile
echo "# vtk python"															>> $propfile
echo "#"																	>> $propfile
echo "vcell.vtkPythonExecutablePath = $installedPython"						>> $propfile
echo "vcell.pythonScriptsPath = $installedPythonScriptsDir"					>> $propfile
echo "##set if needed to pick up python modules"							>> $propfile
echo "#vcell.vtkPythonModulePath ="											>> $propfile

#if [ "$isMac" = true ]; then
#	curl "http://localhost:8080/job/NumericsMulti/platform=macos/lastSuccessfulBuild/artifact/*zip*/archive.zip" -o "$targetRootDir/mac64.zip"
#else
#	curl "http://localhost:8080/job/NumericsMulti/platform=linux64/lastSuccessfulBuild/artifact/*zip*/archive.zip" -o "$targetRootDir/linux64.zip"
#fi

echo "vcell_server_sitedir is $vcell_server_sitedir"
echo "vcell_pathto_sitedir is $vcell_pathto_sitedir"

if [ "$vcell_server_sitedir" == "$vcell_pathto_sitedir" ]
then
	echo "copying to local installation directory"
	mkdir -p $installedSolversDir
	mkdir -p $installedConfigsDir
	mkdir -p $installedPythonScriptsDir
	mkdir -p $installedJarsDir
	mkdir -p $installedNativelibsDir
	mkdir -p $installedInstallersDir
	mkdir -p $installedHtclogsDir
	mkdir -p $installedJmsBlobFilesDir
	mkdir -p $installedLogDir
	mkdir -p $installedTmpDir
	mkdir -p $installedJavaprefsDir
	mkdir -p $installedSystemPrefsDir
	mkdir -p $installedPrimarydataDir
	mkdir -p $installedSecondarydataDir
	mkdir -p $installedParalleldataDir
	mkdir -p $installedExportDir
	mkdir -p $installedDocrootDir
	mkdir -p $installedWebappDir
	mkdir -p $installedJmsDataDir
	mkdir -p $installedJmsLogDir
	
	rm $installedJarsDir/*
	rm $installedNativelibsDir/*
	rm $installedSolversDir/*
	# install externally build solvers on server (temporary solution prior to complete build automation).
	if [ "${skip_extra_solvers}" = false ] && [ -e "${installedSolversDir}/../extra-solvers.tgz" ]; then 
		tar xzf "${installedSolversDir}/../extra-solvers.tgz" --directory="${installedSolversDir}"
	fi
	rm $installedInstallersDir/*
	
	cp -p $stagingConfigsDir/*		$installedConfigsDir
	cp -p $stagingJarsDir/*			$installedJarsDir
	cp -p -R $stagingPythonScriptsDir/*	$installedPythonScriptsDir
	cp -p $stagingNativelibsDir/*	$installedNativelibsDir
	cp -p $projectSolversDir/*		$installedSolversDir
	cp -p $stagingInstallersDir/*	$installedInstallersDir
	cp -p -R $apiDocrootDir/*		$installedDocrootDir
	cp -p -R $apiWebappDir/*			$installedWebappDir
	# set execute permissions on scripts
	pushd $installedConfigsDir
	for f in *; do if [ -z "${f//[^.]/}" ]; then chmod +x "$f"; fi done
	popd
	pushd $installedSolversDir
	for f in *; do if [ -z "${f//[^.]/}" ]; then chmod +x "$f"; fi done
	popd

	if [ ! -z "$vcell_installer_scp_destination" ]; then
		scp ${installedInstallersDir}/* ${vcell_installer_scp_destination}
	fi
	
	if [ "$restart" = true ]; then
		echo "RESTARTING VCELL"
		pushd $installedConfigsDir
		./vcell --debug stop all
		rc=$?
		if [ "$rc" -ne 0 ]; then
			echo "failed to stop vcell"
			exit 1
		fi
		./vcell --debug start all
		rc=$?
		if [ "$rc" -ne 0 ]; then
			echo "failed to start vcell"
			exit 1
		fi
		popd
	fi
	

else
	#
	# remote filesystem
	#   don't bother trying to create primary/secondary/parallel data dirs
	#   dont create export directory - probably uses common export directory
	#
	echo "copying to remote installation via shared file system"
	echo "creating dirs"
	mkdir -p $pathto_SolversDir
	mkdir -p $pathto_ConfigsDir
	mkdir -p $pathto_PythonScriptsDir
	mkdir -p $pathto_JarsDir
	mkdir -p $pathto_NativelibsDir
	mkdir -p $pathto_InstallersDir
	mkdir -p $pathto_HtclogsDir
	mkdir -p $pathto_JmsBlobFilesDir
	mkdir -p $pathto_LogDir
	mkdir -p $pathto_TmpDir
	mkdir -p $pathto_JavaprefsDir
	mkdir -p $pathto_SystemPrefsDir
	mkdir -p $pathto_DocrootDir
	mkdir -p $pathto_WebappDir
	mkdir -p $pathto_JmsDataDir
	mkdir -p $pathto_JmsLogDir
	#mkdir -p $pathto_PrimarydataDir
	#mkdir -p $pathto_SecondarydataDir
	#mkdir -p $pathto_ParalleldataDir
	#mkdir -p $pathto_ExportDir
	
	rm $pathto_JarsDir/*
	rm $pathto_NativelibsDir/*
#	rm $pathto_SolversDir/*
	rm $pathto_InstallersDir/*

	echo "installing scripts to configs (1/8)"
	cp -p $stagingConfigsDir/*		$pathto_ConfigsDir
	echo "installing jar files (2/8)"
	cp -p $stagingJarsDir/*			$pathto_JarsDir
	echo "installing nativelibs (3/8)"
	cp -p $stagingNativelibsDir/*	$pathto_NativelibsDir
	echo "installing python scripts (4/8)"
	cp -p -R $stagingPythonScriptsDir/*	$pathto_PythonScriptsDir
#	echo "installing server-side solvers (5/8)"
#	cp -p $projectSolversDir/*		$pathto_SolversDir
	echo "installing client installers to server (6/8)"
	cp -p $stagingInstallersDir/*	$pathto_InstallersDir
	echo "installing vcellapi docroot dir to server (7/8)"
	cp -p -R $apiDocrootDir/*		$pathto_DocrootDir
	echo "installing vcellapi webapp dir to server (8/8)"
	cp -p -R $apiWebappDir/*		$pathto_WebappDir
	# set execute permissions on scripts
	pushd $pathto_ConfigsDir
	for f in *; do if [ -z "${f//[^.]/}" ]; then chmod +x "$f"; fi done
	popd
	pushd $pathto_SolversDir
	for f in *; do if [ -z "${f//[^.]/}" ]; then chmod +x "$f"; fi done
	popd
	echo "done with installation"

	echo ""
	echo "REMEMBER ... move installers to apache if applicable"
	echo ""
	echo "scp $pathto_InstallersDir/* ${vcell_installer_scp_destination}"
	echo ""
	echo " then, don't forget to update symbolic links to <latest> installers"
	echo ""
fi


