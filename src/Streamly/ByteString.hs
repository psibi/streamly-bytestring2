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

fromFile
  :: (MonadResource m, MonadIO m, Streaming t, MonadTrans t, MonadIO (t m))
  => FilePath -> t m ByteString
fromFile fp =
  bracketBS
    (IO.openBinaryFile fp IO.ReadMode)
    (IO.hClose)
    (\handle -> hGetSome defaultChunkSize handle)

toFile
  :: (MonadResource m, Streaming t)
  => FilePath -> t m ByteString -> m ()
toFile fp stream = do
  (key, handle) <- allocate (IO.openBinaryFile fp IO.WriteMode) IO.hClose
  clean key handle stream'
  where
    stream' = toStream stream
    clean key h stream =
      let stop = return ()
          yield a Nothing = do
            liftIO (BS.hPut h a)
            liftIO $ release key
          yield a (Just x) = liftIO (BS.hPut h a) >> clean key h x
      in (runStream stream) Nothing stop yield

bracketBS
  :: (Streaming t, MonadResource m, Monad (t m), MonadTrans t)
  => IO a -> (a -> IO ()) -> (a -> t m b) -> t m b
bracketBS alloc free inside = do
  (key :: ReleaseKey, seed :: a) <- lift $ allocate alloc free
  clean key (inside seed)
  where
    clean key sr =
      fromStream $
      Stream $
      \ctx stp yld -> do
        let yield a Nothing = do
              yld a Nothing
              liftIO $ release key
              stp
            yield a (Just (r :: Stream m r)) = do
              yld a (Just (toStream $ clean key (fromStream r)))
            stop = do
              liftIO $ release key
              stp
        (runStream (toStream sr)) ctx stop yield

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
