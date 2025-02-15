/*
 * Copyright (C) 1999-2011 University of Connecticut Health Center
 *
 * Licensed under the MIT License (the "License").
 * You may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 *
 *  http://www.opensource.org/licenses/mit-license.php
 */

package cbit.vcell.message.server.bootstrap;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.lang.management.ManagementFactory;
import java.rmi.RemoteException;
import java.rmi.server.ServerNotActiveException;
import java.rmi.server.UnicastRemoteObject;
import java.util.Date;

import javax.management.MBeanServer;
import javax.management.ObjectName;

import org.vcell.db.ConnectionFactory;
import org.vcell.db.DatabaseService;
import org.vcell.db.KeyFactory;
import org.vcell.service.VCellServiceHelper;
import org.vcell.util.AuthenticationException;
import org.vcell.util.DataAccessException;
import org.vcell.util.LifeSignThread;
import org.vcell.util.PermissionException;
import org.vcell.util.SessionLog;
import org.vcell.util.UseridIDExistsException;
import org.vcell.util.document.User;
import org.vcell.util.document.UserInfo;
import org.vcell.util.document.UserLoginInfo;
import org.vcell.util.document.VCellServerID;
import org.vcell.util.logging.Logging;

import cbit.vcell.message.VCMessagingService;
import cbit.vcell.message.server.ManageUtils;
import cbit.vcell.message.server.ServerMessagingDelegate;
import cbit.vcell.message.server.ServiceInstanceStatus;
import cbit.vcell.message.server.ServiceProvider;
import cbit.vcell.message.server.ServiceSpec.ServiceType;
import cbit.vcell.message.server.dispatcher.SimulationDatabase;
import cbit.vcell.message.server.dispatcher.SimulationDatabaseDirect;
import cbit.vcell.message.server.jmx.BootstrapMXBean;
import cbit.vcell.message.server.jmx.VCellServiceMXBean;
import cbit.vcell.message.server.jmx.VCellServiceMXBeanImpl;
import cbit.vcell.modeldb.AdminDBTopLevel;
import cbit.vcell.modeldb.DatabasePolicySQL;
import cbit.vcell.modeldb.DatabaseServerImpl;
import cbit.vcell.modeldb.LocalAdminDbServer;
import cbit.vcell.mongodb.VCMongoMessage;
import cbit.vcell.mongodb.VCMongoMessage.ServiceName;
import cbit.vcell.resource.PropertyLoader;
import cbit.vcell.resource.StdoutSessionLog;
import cbit.vcell.resource.StdoutSessionLogConcurrent;
import cbit.vcell.resource.StdoutSessionLogConcurrent.LifeSignInfo;
import cbit.vcell.resource.StdoutSessionLogConcurrentRmi;
import cbit.vcell.server.AdminDatabaseServer;
import cbit.vcell.server.VCellBootstrap;
import cbit.vcell.server.VCellConnection;
import cbit.vcell.server.VCellServer;
import cbit.vcell.server.WatchdogMonitor;
import cbit.vcell.simdata.Cachetable;
import cbit.vcell.simdata.DataSetControllerImpl;
/**
 * This class was generated by a SmartGuide.
 * 
 */
@SuppressWarnings("serial")
public class LocalVCellBootstrap extends UnicastRemoteObject implements VCellBootstrap {
	private LocalVCellServer localVCellServer = null;
	private AdminDatabaseServer adminDbServer = null;
	private SessionLog sessionLog = new StdoutSessionLog(PropertyLoader.ADMINISTRATOR_ACCOUNT);
	private BootstrapMXBean bootstrapMXBean = new BootstrapMXBeanImpl();
	
	public class BootstrapMXBeanImpl implements BootstrapMXBean {
		public BootstrapMXBeanImpl(){
		}
		@Override
		public int getConnectedUserCount(){
			return localVCellServer.getServerInfo().getConnectedUsers().length;
		}
		@Override
		public String getConnectedUserNames(){
			StringBuilder userNames = new StringBuilder();
			User[] users = localVCellServer.getServerInfo().getConnectedUsers();
			for (User user : users){
				userNames.append(user.getName()+" ");
			}
			return userNames.toString();
		}
	}
/**
 * This method was created by a SmartGuide.
 * @exception java.rmi.RemoteException The exception description.
 */
private LocalVCellBootstrap(String hostName, AdminDatabaseServer adminDbServer, VCMessagingService vcMessagingService, SimulationDatabase simulationDatabase, int rmiPort) throws RemoteException, FileNotFoundException, DataAccessException {
	super(rmiPort);
	this.adminDbServer = adminDbServer;
	Cachetable dataCachetable = new Cachetable(10*Cachetable.minute);
	DataSetControllerImpl datasetControllerImpl = new DataSetControllerImpl(sessionLog,dataCachetable, 
			new File("no-primary-sim-data-dir"), 
			new File("no-secondary-sim-data-dir"));
	this.localVCellServer = new LocalVCellServer(hostName, vcMessagingService, adminDbServer, simulationDatabase, datasetControllerImpl, rmiPort);
}
/**
 * This method was created by a SmartGuide.
 * @return cbit.vcell.server.DataSetController
 * @exception java.lang.Exception The exception description.
 */
public VCellConnection getVCellConnection(UserLoginInfo userLoginInfo) throws DataAccessException, AuthenticationException {
	try {
		try {
			String ch = getClientHost();
			System.out.println(ch);
		} catch (ServerNotActiveException e) {
			e.printStackTrace();
		}
		
		VCellConnection vcConn = localVCellServer.getVCellConnection(userLoginInfo);
		if (vcConn!=null){
			sessionLog.print("LocalVCellBootstrap.getVCellConnection(" + userLoginInfo.getUserName() +") <<<<SUCCESS>>>>");
		}else{
			sessionLog.print("LocalVCellBootstrap.getVCellConnection(" + userLoginInfo.getUserName() +") <<<<RETURNED NULL>>>>");
		}
		return vcConn;
	}catch (RemoteException e){
		sessionLog.exception(e);
		throw new DataAccessException(e.getMessage());
	}catch (FileNotFoundException e){
		sessionLog.exception(e);
		throw new DataAccessException(e.getMessage());
	}catch (java.sql.SQLException e){
		sessionLog.exception(e);
		throw new DataAccessException(e.getMessage());
	}
}
/**
 * This method was created by a SmartGuide.
 * @return cbit.vcell.server.DataSetController
 * @exception java.lang.Exception The exception description.
 */
public VCellServer getVCellServer(User user, UserLoginInfo.DigestedPassword digestedPassword) throws DataAccessException, AuthenticationException, PermissionException {
	//
	// Authenticate User
	//
	boolean bAuthenticated = adminDbServer.getUser(user.getName(),digestedPassword, false).compareEqual(user);
	if (!bAuthenticated){
		sessionLog.print("LocalVCellBootstrap.getVCellServer(" + user +"), didn't authenticate");
		throw new AuthenticationException("Authentication Failed for user " + user.getName());
	}else if (user.getName().equals(PropertyLoader.ADMINISTRATOR_ACCOUNT)){
		sessionLog.print("LocalVCellBootstrap.getVCellServer(" + user + "), returning remote copy of VCellServer");
		return localVCellServer;
	}else{
		sessionLog.print("LocalVCellBootstrap.getVCellServer(" + user + "), insufficient privilege for user "+user.getName());
		throw new PermissionException("insufficient privilege for user "+user.getName());
	}
}
/**
 * Insert the method's description here.
 * Creation date: (6/8/2006 3:25:26 PM)
 * @return java.lang.String
 */
public java.lang.String getVCellSoftwareVersion() {
	String ver = PropertyLoader.getRequiredProperty(PropertyLoader.vcellSoftwareVersion);
	sessionLog.print("LocalVCellBootstrap.getVCellSoftwareVersion() : " + ver);
	return ver;
}
/**
 * main entrypoint - starts the application
 * @param args java.lang.String[]
 */
public static void main(java.lang.String[] args) {
	Logging.init();
	String MESSAGING = "messaging";
	if (args.length != 4) {
		System.out.println("usage: cbit.vcell.server.LocalVCellBootstrap host port messaging [logdir|-] \n");
		System.out.println(" example -  cbit.vcell.server.LocalVCellBootstrap nrcam.vcell.uchc.edu 40099 messaging /share/apps/vcell/logs");
		System.exit(1);
	}
	try {
		//
		// Create and install a security manager
		//
		//System.setSecurityManager(new RMISecurityManager());

		Thread.currentThread().setName("Application");
		PropertyLoader.loadProperties(REQUIRED_SERVICE_PROPERTIES);

		//
		// get Host and Port
		//
		String host = args[0];
		if (host.equals("localhost")){
			try {
				host = java.net.InetAddress.getLocalHost().getHostName();
			}catch (java.net.UnknownHostException e){
				// do nothing, "localhost" is ok
			}
		}
		int rmiPort = Integer.parseInt(args[1]);
		
		Integer serviceOrdinal = new Integer(rmiPort);
		VCMongoMessage.serviceStartup(ServiceName.bootstrap, serviceOrdinal, args);
		
		//
		// Redirect output to the logfile (append if exists)
		//
		OutputStream logOutputStream = null;
		if (args[3]!=null){
			String logdir = args[3];
			ServiceInstanceStatus serviceInstanceStatus = new ServiceInstanceStatus(VCellServerID.getSystemServerID(), ServiceType.RMI, serviceOrdinal, ManageUtils.getHostName(), new Date(), true);
			logOutputStream = ServiceProvider.initLog(serviceInstanceStatus, logdir);
		}
		
		//
		// decide whether it will be a Primary or Slave Server
		//
		String serverConfig = args[2];
		if (!serverConfig.equals(MESSAGING)){
			throw new Exception("expecting '" + MESSAGING + "' as third argument");
		}
		VCMessagingService vcMessagingService = VCellServiceHelper.getInstance().loadService(VCMessagingService.class);
		vcMessagingService.setDelegate(new ServerMessagingDelegate());
		
		SessionLog log;
		if (logOutputStream != null) {
			StdoutSessionLogConcurrent sslc = 
				new StdoutSessionLogConcurrentRmi("local(unauthenticated)_administrator",logOutputStream, new LifeSignInfo()); 
			final PrintStream concurrentPrintStream = sslc.printStreamFacade();
			System.setOut(concurrentPrintStream);
			System.setErr(concurrentPrintStream);
			log = sslc;
		}
		else {
			log = new StdoutSessionLog("local(unauthenticated)_administrator");
			int lifeSignMessageInterval_MS = 3*60000; //3 minutes -- possibly make into a property later
			new LifeSignThread(log,lifeSignMessageInterval_MS).start();   
		}
		
		ConnectionFactory conFactory = null;
		int tryCount = 0;
		Exception conFactoryException = null;
		do{
			try{
				conFactoryException = null;
				conFactory = DatabaseService.getInstance().createConnectionFactory(log);
			}catch(Exception e){
				e.printStackTrace();
				conFactoryException = e;
			}
			Thread.sleep(5000);
		}while(tryCount++ < 10);
		if(conFactory == null){
			throw new Exception("Couldn't create OraclePoolingConnectionFactory after "+tryCount+" tries.",conFactoryException);
		}
		
		KeyFactory keyFactory = conFactory.getKeyFactory();
		DatabasePolicySQL.bSilent=true;
		//
		// don't timeout entries, and use vcell.properties for cacheSize
		//
		LocalVCellConnection.setDatabaseResources(conFactory,keyFactory);
		
		AdminDatabaseServer adminDbServer = new LocalAdminDbServer(conFactory,keyFactory,log);
		AdminDBTopLevel adminDbTopLevel = new AdminDBTopLevel(conFactory, log);
		DatabaseServerImpl databaseServerImpl = new DatabaseServerImpl(conFactory, keyFactory, log);
		SimulationDatabase simulationDatabase = new SimulationDatabaseDirect(adminDbTopLevel, databaseServerImpl, false, log);
		LocalVCellBootstrap localVCellBootstrap = new LocalVCellBootstrap(host+":"+rmiPort,adminDbServer,vcMessagingService,simulationDatabase, rmiPort);

		//
		// JMX registration
		//
        MBeanServer mbs = ManagementFactory.getPlatformMBeanServer();
        mbs.registerMBean(new VCellServiceMXBeanImpl(), new ObjectName(VCellServiceMXBean.jmxObjectName));
        mbs.registerMBean(localVCellBootstrap.bootstrapMXBean, new ObjectName(BootstrapMXBean.jmxObjectName));
        
		//
		// spawn the WatchdogMonitor (which spawns the RMI registry, and binds the localVCellBootstrap)
		//
		long minuteMS = 60000;
		long monitorSleepTime = 20*minuteMS;
		monitorSleepTime = Long.MAX_VALUE; //TEST: only run once
		String rmiUrl = "//" + host + ":" + rmiPort + "/VCellBootstrapServer";
		Thread watchdogMonitorThread = new Thread(new WatchdogMonitor(monitorSleepTime,rmiPort,rmiUrl,localVCellBootstrap,serverConfig),"WatchdogMonitor");
		watchdogMonitorThread.setDaemon(true);
		watchdogMonitorThread.setName("WatchdogMonitor");
		watchdogMonitorThread.start();
	} catch (Throwable e) {
		System.out.println("LocalVCellBootstrap err: " + e.getMessage());
		e.printStackTrace();
	}
}
public UserInfo insertUserInfo(UserInfo newUserInfo) throws RemoteException,DataAccessException,UseridIDExistsException {
	return adminDbServer.insertUserInfo(newUserInfo);
}
public void sendLostPassword(String userid) throws RemoteException,DataAccessException {
	adminDbServer.sendLostPassword(userid);
}

private static final String REQUIRED_SERVICE_PROPERTIES[] = {
		PropertyLoader.vcellServerIDProperty,
		PropertyLoader.vcellSoftwareVersion,
		PropertyLoader.installationRoot,
		PropertyLoader.dbConnectURL,
		PropertyLoader.dbDriverName,
		PropertyLoader.dbUserid,
		PropertyLoader.dbPassword,
		PropertyLoader.mongodbHost,
		PropertyLoader.mongodbPort,
		PropertyLoader.mongodbDatabase,
		PropertyLoader.jmsURL,
		PropertyLoader.jmsUser,
		PropertyLoader.jmsPassword,
		PropertyLoader.jmsBlobMessageTempDir
	};


}
