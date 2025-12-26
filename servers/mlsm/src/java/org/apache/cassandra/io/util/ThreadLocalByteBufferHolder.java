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

import java.nio.ByteBuffer;
import java.util.EnumMap;

import io.netty.util.concurrent.FastThreadLocal;

import org.apache.cassandra.io.compress.BufferType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Utility class that allow buffers to be reused by storing them in a thread local instance.
 */
public final class ThreadLocalByteBufferHolder
{
    
    private static final Logger logger = LoggerFactory.getLogger(ThreadLocalByteBufferHolder.class);
    private static final EnumMap<BufferType, FastThreadLocal<ByteBuffer>> reusableBBHolder = new EnumMap<>(BufferType.class);
    // Convenience variable holding a ref to the current resuableBB to avoid map lookups
    private final FastThreadLocal<ByteBuffer> reusableBB;

    static
    {
        for (BufferType bbType : BufferType.values())
        {
            reusableBBHolder.put(bbType, new FastThreadLocal<ByteBuffer>()
            {
                protected ByteBuffer initialValue()
                {
                    return ByteBuffer.allocate(0);
                }
            });
        }
    };

    /**
     * The type of buffer that will be returned
     */
    private final BufferType bufferType;

    public ThreadLocalByteBufferHolder(BufferType bufferType, Boolean useDirectIO)
    {
        this.bufferType = useDirectIO ? BufferType.OFF_HEAP : bufferType;
        this.reusableBB = reusableBBHolder.get(bufferType);
    }

    public ThreadLocalByteBufferHolder(BufferType bufferType)
    {
        this(bufferType, false);
    }

    /**
     * Returns the buffer for the current thread.
     *
     * <p>If the buffer for the current thread does not have a capacity large enough. A new buffer with the requested
     *  size will be instatiated an will replace the existing one.</p>
     *
     * @param size the buffer size
     * @return the buffer for the current thread.
     */
    public ByteBuffer getBuffer(int size)
    {
        return getBuffer(size, false);
    }

    
    public ByteBuffer getBuffer(int size, boolean useDirectIO)
    {
        ByteBuffer buffer = reusableBB.get();
        if (buffer.capacity() < size + DirectIOUtils.BLOCK_SIZE)
        {
            FileUtils.clean(buffer);
            // if(buffer.isDirect() && useDirectIO)
            // {
            //     logger.debug("HATSERROR: We want the useDirectIO: {}, but we get a buffer type: {}", useDirectIO, bufferType);
            // }
            // We allocate a buffer that is BLOCK_SIZE larger than the requested size to allow for the buffer to be aligned
            buffer = useDirectIO ? 
                     BufferType.OFF_HEAP.allocate(size + DirectIOUtils.BLOCK_SIZE, true) : 
                     bufferType.allocate(size);
            reusableBB.set(buffer);
        }
        buffer.clear().limit(size);
        return buffer;
    }
}
