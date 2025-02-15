/*
 * Copyright (C) 1999-2011 University of Connecticut Health Center
 *
 * Licensed under the MIT License (the "License").
 * You may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 *
 *  http://www.opensource.org/licenses/mit-license.php
 */

package org.vcell.util;


/**
 * This type was created in VisualAge.
 */
public class Extent implements java.io.Serializable, Matchable {
	private double x;
	private double y;
	private double z;

/**
 * Origin constructor comment.
 */
public Extent(double newX,double newY,double newZ) throws IllegalArgumentException {
	if (newX<=0 || newY<=0 || newZ<=0){
		throw new IllegalArgumentException("extent=("+newX+","+newY+","+newZ+") must be > 0 for x,y,z");
	}
	this.x = newX;
	this.y = newY;
	this.z = newZ;
}


/**
 * This method was created in VisualAge.
 * @return boolean
 * @param matchable cbit.util.Matchable
 */
public boolean compareEqual(Matchable matchable) {
	if (matchable instanceof Extent){
		Extent extent = (Extent)matchable;

		if ((extent.getX() != getX()) || (extent.getY() != getY()) || (extent.getZ() != getZ())){
			return false;
		}
		return true;
	}else{
		return false;
	}
}


/**
 * This method was created in VisualAge.
 * @return double
 */
public double getX() {
	return x;
}


/**
 * This method was created in VisualAge.
 * @return double
 */
public double getY() {
	return y;
}


/**
 * This method was created in VisualAge.
 * @return double
 */
public double getZ() {
	return z;
}


/**
 * This method was created in VisualAge.
 * @return java.lang.String
 */
public String toString() {
	return "("+getX()+","+getY()+","+getZ()+")";
}
}
