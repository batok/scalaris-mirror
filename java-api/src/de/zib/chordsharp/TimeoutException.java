/**
 *  Copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */
package de.zib.chordsharp;

import com.ericsson.otp.erlang.OtpErlangException;

/**
 * Exception that is thrown when a read or write operation on a chordsharp ring
 * fails due to a timeout.
 * 
 * @author Nico Kruber, kruber@zib.de
 */
public class TimeoutException extends OtpErlangException {
	/**
	 * class version for serialisation
	 */
	private static final long serialVersionUID = 1L;

	/**
	 * Creates the exception with no message.
	 */
	public TimeoutException() {
	}

	/**
	 * Creates the exception with the given message.
	 * 
	 * @param msg
	 *            message of the exception
	 */
	public TimeoutException(String msg) {
		super(msg);
	}
}
