package cbit.vcell.message;

import java.io.Serializable;

import org.vcell.util.SessionLog;

public class VCRpcMessageHandler implements VCQueueConsumer.QueueListener {
	private Object serviceImplementation = null;
	private VCellQueue queue = null;
	private SessionLog log = null;

	public VCRpcMessageHandler(Object serviceImplementation, VCellQueue queue, SessionLog log) {
		this.serviceImplementation = serviceImplementation;
		this.queue = queue;
		this.log = log;
	}
	
	public void onQueueMessage(VCMessage rpcVCMessage, VCMessageSession session) {
		session.getDelegate().onMessageReceived(rpcVCMessage,queue);
		Serializable object = (Serializable)rpcVCMessage.getObjectContent();
		if (!(object instanceof VCRpcRequest)){
			throw new RuntimeException("expecting RpcRequest in message");
		}
		VCRpcRequest vcRpcRequest = null;
		if (object instanceof VCRpcRequest){
			vcRpcRequest = (VCRpcRequest)object;
		}
		
		java.io.Serializable returnValue = null;
		try {
			//
			// invoke the local RPC implementation and collect either the return value or the exception that was thrown
			//
			returnValue = (Serializable) vcRpcRequest.rpc(serviceImplementation, log);
		} catch (Exception ex) {
			log.exception(ex);
			returnValue = ex; // if exception occurs, send client the exception
		}

		// check the return value for non-seriablable objects
		if (returnValue != null && returnValue.getClass().isArray()) {
			Class<?> componentClass = returnValue.getClass().getComponentType();
			if (!componentClass.isPrimitive() && !Serializable.class.isAssignableFrom(componentClass)) {
				returnValue = new ClassCastException("Not serializable:" + componentClass);
			}
		}

		// reply to "reply-to" queue with the return value or exception.
		long clientTimeoutMS = Long.parseLong(cbit.vcell.resource.PropertyLoader.getProperty(cbit.vcell.resource.PropertyLoader.vcellClientTimeoutMS, "1200000")); 
		VCellQueue replyTo = (VCellQueue)rpcVCMessage.getReplyTo();
		
		//
		// use MessageProducerSessionJms to create the replyMessage (allows "Blob" messages to be formed as needed).
		//
		VCMessage vcReplyMessage = null;
		synchronized (session){
			vcReplyMessage = session.createObjectMessage(returnValue);
		}

		vcReplyMessage.setStringProperty(VCMessagingConstants.METHOD_NAME_PROPERTY, vcRpcRequest.getMethodName());
		vcReplyMessage.setCorrelationID(rpcVCMessage.getMessageID());
		Boolean persistent = new Boolean(false);
		try {
			synchronized (session) {				
				session.sendQueueMessage(replyTo, vcReplyMessage, persistent, clientTimeoutMS);
System.out.println("sent reply message with JMSCorrelationID to "+vcReplyMessage.getCorrelationID()+", and messageID = "+vcReplyMessage.getMessageID());
			}
		} catch (VCMessagingException e) {
			log.exception(e);
			throw new RuntimeException("error sending reply to RPC message: "+e.getMessage(),e);
		}
		session.getDelegate().onRpcRequestProcessed(vcRpcRequest,rpcVCMessage);
	}
}