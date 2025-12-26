/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.cassandra.io.util;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.channels.WritableByteChannel;
// import java.nio.file.OpenOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;

import org.apache.cassandra.io.FSReadError;
import org.apache.cassandra.io.directio.DirectRandomAccessFile;
import org.apache.cassandra.utils.NativeLibrary;
import org.apache.cassandra.utils.concurrent.RefCounted;
import org.apache.cassandra.utils.concurrent.SharedCloseableImpl;
// import java.io.File;


import com.sun.nio.file.ExtendedOpenOption;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * A proxy of a FileChannel that:
 *
 * - implements reference counting
 * - exports only thread safe FileChannel operations
 * - wraps IO exceptions into runtime exceptions
 *
 * Tested by RandomAccessReaderTest.
 */
public final class ChannelProxy extends SharedCloseableImpl
{
    private final File file;
    private final String filePath;
    public final FileChannel channel;
    
    public boolean useDirectIO;
    private static final Logger logger = LoggerFactory.getLogger(ChannelProxy.class);

    public static FileChannel openChannel(File file, boolean useDirectIO)
    {
        try
        {
            return useDirectIO ? 
                   FileChannel.open(file.toPath(), StandardOpenOption.READ, ExtendedOpenOption.DIRECT) : 
                   FileChannel.open(file.toPath(), StandardOpenOption.READ);
                //    FileChannel.open(file.toPath(), StandardOpenOption.READ, (OpenOption) Enum.valueOf((Class<? extends Enum>) Class.forName("com.sun.nio.file.ExtendedOpenOption"), "DIRECT"));
            // return FileChannel.open(file.toPath(), StandardOpenOption.READ);
        }
        catch (Exception e)
        {
            throw new RuntimeException(e);
        }
    }

    public static FileChannel openChannel(File file)
    {
        try
        {
            return FileChannel.open(file.toPath(), StandardOpenOption.READ);
        }
        catch (IOException e)
        {
            throw new RuntimeException(e);
        }
    }

    
    public ChannelProxy(String filePath, FileChannel channel, boolean useDirectIO)
    {
        super(new Cleanup(filePath, channel));
        this.file = new File(filePath);
        this.filePath = filePath;
        this.channel = channel;
        this.useDirectIO = useDirectIO;
    }


    public ChannelProxy(String path)
    {
        this (new File(path), false);
    }

    public ChannelProxy(File file)
    {
        this(file, false);
    }

    public ChannelProxy(File file, FileChannel channel)
    {
        // super(new Cleanup(file.path(), channel));
        this(file.path(), channel, false);
    }

    public ChannelProxy(File file, boolean useDirectIO) {
        this(file.path(), openChannel(file, useDirectIO), useDirectIO);
    }

    public ChannelProxy(String path, boolean useDirectIO) {
        this(new File(path), useDirectIO);
    }


    public ChannelProxy(ChannelProxy copy)
    {
        super(copy);

        this.file = copy.file;
        this.filePath = copy.filePath;
        this.channel = copy.channel;
        this.useDirectIO = copy.useDirectIO;
    }

    private final static class Cleanup implements RefCounted.Tidy
    {
        final String filePath;
        final FileChannel channel;

        Cleanup(String filePath, FileChannel channel)
        {
            this.filePath = filePath;
            this.channel = channel;
        }

        public String name()
        {
            return filePath;
        }

        public void tidy()
        {
            try
            {
                channel.close();
            }
            catch (IOException e)
            {
                throw new FSReadError(e, filePath);
            }
        }
    }

    /**
     * {@link #sharedCopy()} can not be used if thread will be interruped, as the backing channel will be closed.
     *
     * @return a new channel instance
     */
    public final ChannelProxy newChannel()
    {
        return new ChannelProxy(filePath);
    }

    public ChannelProxy sharedCopy()
    {
        return new ChannelProxy(this);
    }

    public String filePath()
    {
        return filePath;
    }

    public File file()
    {
        return file;
    }

    public int read(ByteBuffer buffer, long position, int length)
    {
        try
        {
            // FIXME: consider wrapping in a while loop
            // return channel.read(buffer, position);
            return useDirectIO ? DirectIOUtils.read(channel, buffer, position, length) : channel.read(buffer, position);
        }
        catch (IOException e)
        {
            throw new FSReadError(e, filePath);
        }
    }

    public int read(ByteBuffer buffer, long position)
    {
        return read(buffer, position, 0);
    }

    public long transferTo(long position, long count, WritableByteChannel target)
    {
        try
        {
            return channel.transferTo(position, count, target);
        }
        catch (IOException e)
        {
            throw new FSReadError(e, filePath);
        }
    }

    public MappedByteBuffer map(FileChannel.MapMode mode, long position, long size)
    {
        try
        {
            return channel.map(mode, position, size);
        }
        catch (IOException e)
        {
            throw new FSReadError(e, filePath);
        }
    }

    public long size()
    {
        try
        {
            return channel.size();
        }
        catch (IOException e)
        {
            throw new FSReadError(e, filePath);
        }
    }

    public int getFileDescriptor()
    {
        return NativeLibrary.getfd(channel);
    }

    @Override
    public String toString()
    {
        return filePath();
    }

    public static void main(String[] args) throws IOException {
		boolean directIO = false;
		int bufferSize =  (1<<30); // 4gb
		String inputFile = "/home/hats/test/testfile";
		String outputFile = "/home/hats/test/outputfile";

		if(directIO) 
		{			
			byte[] buf = new byte[bufferSize];
			DirectRandomAccessFile fin = new DirectRandomAccessFile(new File(inputFile), "r", bufferSize);
			DirectRandomAccessFile fout = new DirectRandomAccessFile(new File(outputFile), "rw", bufferSize);
			
			while (fin.getFilePointer() < fin.length()) {
				int remaining = (int)Math.min(bufferSize, fin.length()-fin.getFilePointer());
				fin.read(buf,0,remaining);
				fout.write(buf,0,remaining);
			}
			
			fin.close();
			fout.close();
		}
		else {
            InputStream in = null;
            OutputStream out = null;
            try {
                in = new FileInputStream(inputFile);
                out = new FileOutputStream(outputFile);

                byte[] buffer = new byte[bufferSize];
                int length;
                while ((length = in.read(buffer)) != -1) {
                    out.write(buffer, 0, length);
                }
            } finally {
                if (in != null) {
                    in.close();
                }
                if (out != null) {
                    out.close();
                }
            }
        }
    }
}
