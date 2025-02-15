/*
 * Copyright (C) 1999-2011 University of Connecticut Health Center
 *
 * Licensed under the MIT License (the "License").
 * You may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 *
 *  http://www.opensource.org/licenses/mit-license.php
 */

package org.vcell.util.document;
import java.util.Arrays;

import org.vcell.util.Immutable;
import org.vcell.util.Matchable;

/**
 * This type was created in VisualAge.
 */
@SuppressWarnings("serial")
public class User implements java.io.Serializable, Matchable, Immutable {
	private String userName = null;
	private KeyValue key = null;
	private static final String VCellTestAccountName = "vcelltestaccount";

	public static final String[] publishers = {"frm","schaff","ion"};

	public static final User tempUser = new User("temp",new KeyValue("123"));
	/**
 * User constructor comment.
 */
public User(String userid, KeyValue key) {
	this.userName = userid;
	this.key = key;
}


/**
 * @return {@link #equals(Object)}
 */
public boolean compareEqual(Matchable obj) {
	return equals(obj);
}

/**
 * @return true if {@link #key}s match
 */
public boolean equals(Object obj) {
	if (obj == this){
		return true;
	}

	User user = null;
	if (!(obj instanceof User)){
		return false;
	}
	user = (User)obj;

	return org.vcell.util.Compare.isEqual(key,user.key);
}


/**
 * This method was created in VisualAge.
 * @return long
 */
public KeyValue getID() {
	return key;
}


/**
 * This method was created in VisualAge.
 * @return java.lang.String
 */
public String getName() {
	return userName;
}


/**
 * Insert the method's description here.
 * Creation date: (1/24/01 5:31:05 PM)
 * @return int
 */
public int hashCode() {
	return getName().hashCode();
}

/**
 * Insert the method's description here.
 * Creation date: (5/23/2006 8:33:53 AM)
 * @return boolean
 */
public boolean isPublisher() {
	return Arrays.asList(publishers).contains(userName);
}


/**
 * @return true if this is test account
 */
public boolean isTestAccount() {
	return isTestAccount(getName( ));
}

/**
 * @param accountName non null
 * @return true if accountName is test account
 */
public static boolean isTestAccount(String accountName) {
	return accountName.equals(VCellTestAccountName);
}


/**
 * This method was created in VisualAge.
 * @return java.lang.String
 */
public String toString() {
	return userName+"("+key+")";
}
}
