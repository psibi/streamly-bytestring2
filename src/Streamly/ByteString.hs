{-# LANGUAGE ScopedTypeVariables #-}

module Streamly.ByteString where

import qualified System.IO as IO
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Lazy.Internal
       (foldrChunks, defaultChunkSize)
import Streamly
import Streamly.Core
import Streamly.Streams
import Data.Acquire
import Control.Monad.Trans.Resource
import Control.Monad (unless)
import qualified Data.Streaming.FileRead as FR
import Control.Exception

{-| Convert a handle into a byte stream using a maximum chunk size

    'hGetSome' forwards input immediately as it becomes available, splitting the
    input into multiple chunks if it exceeds the maximum chunk size.
-}
hGetSome
  :: (MonadIO m, Streaming t)
  => Int -> IO.Handle -> t m ByteString
hGetSome size h = fromStream go
  where
    go =
      Stream $
      \_ stp yld -> do
        bs <- liftIO (BS.hGetSome h size)
        if (BS.null bs)
          then stp
          else do
            yld bs (Just go)

bracketBS
  :: (MonadResource m, MonadIO m)
  => IO a -> (a -> IO ()) -> (a -> Stream m ByteString) -> Stream m ByteString
bracketBS alloc free inside = do
  (key :: ReleaseKey, seed :: a) <- lift $ allocate alloc free
  clean key (inside seed)
  where
    clean
      :: (MonadIO m)
      => ReleaseKey -> Stream m ByteString -> Stream m ByteString
    clean key sr =
      Stream $
      \ctx stp yld -> do
        let yield a Nothing = do
              liftIO $ release key
              stp
            yield a (Just r) = yld a (Just r)
        (runStream sr) ctx stp yield

fromFile
  :: (MonadResource m, MonadIO m, Streaming t)
  => FilePath -> t m ByteString
fromFile fp =
  fromStream $
  bracketBS
    (FR.openFile fp)
    (FR.closeFile)
    (\handle -> do
       bs <- liftIO $ FR.readChunk handle
       return bs)

-- clean key sr = do
--   (fr :: ByteString) <- sr
--   if BS.null fr
--     then lift $ release key
--     else undefined
-- Stream $
-- \ctx stp yld -> do
--   let yield a Nothing = do
--         lift $ release key
--         stp
--       yield a (Just r) = undefined -- yld a (Just r)
--   (runStream sr) ctx stp yield
-- fromFile fp =
--   bracket
--     (FR.openFile fp >>= return)
--     (\h -> FR.closeFile h >> return ())
--     (\h -> fromStream (go h))
--   where
--     go h =
--       Stream $
--       \_ stp yld -> do
--         bs <- liftIO (FR.readChunk h)
--         if (BS.null bs)
--           then (liftIO $ FR.closeFile h) >> stp
--           else do
--             yld bs (Just (go h))
-- | Stream bytes from 'stdin'
stdin
  :: (MonadIO m, Streaming t)
  => t m ByteString
stdin = fromHandle IO.stdin

-- | Convert a 'IO.Handle' into a byte stream using a default chunk size
fromHandle
  :: (MonadIO m, Streaming t)
  => IO.Handle -> t m ByteString
fromHandle = hGetSome defaultChunkSize

-- | Write a stream of Strings to an IO Handle.
toHandle
  :: (Streaming t, MonadIO m)
  => IO.Handle -> t m ByteString -> m ()
toHandle h m = go (toStream m)
  where
    go m1 =
      let stop = return ()
          yield a Nothing = liftIO (BS.hPut h a)
          yield a (Just x) = liftIO (BS.hPut h a) >> go x
      in (runStream m1) Nothing stop yield
-- fromFile
--   :: (Streaming t, MonadMask m)
--   => FilePath -> t m a
-- fromFile fp = bracket (FR.openFile fp) FR.closeFile (\h -> fromStream (go h))
--   where
--     go h =
--       Stream $
--       \_ stp yld -> do
--         bs <- liftIO (FR.readChunk h)
--         if (BS.null bs)
--           then (liftIO $ FR.closeFile h) >> stp
--           else do
--             yld bs (Just (go h))
--   :: MonadBaseControl IO m
--   => FilePath -> IO.IOMode -> (IO.Handle -> m a) -> m a
-- withFile fp ioMode action = do
--   let acq = mkAcquire (IO.openFile fp ioMode) (\handle -> IO.hClose handle)
--   with acq action
