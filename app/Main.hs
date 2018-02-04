{-# LANGUAGE FlexibleContexts #-}

module Main where

import Lib
import Streamly.ByteString
import Streamly
import Data.ByteString
import Control.Monad.Trans.Resource

-- import Streamly.Prelude (toHandle)
import qualified System.IO as IO

echo :: IO ()
echo = toHandle IO.stdout (stdin :: StreamT IO ByteString)

myFile
  :: (MonadResource m)
  => StreamT m ByteString
myFile = fromFile "/home/sibi/xebia.md"

myFile2
  :: (MonadResource m)
  => StreamT m ByteString
myFile2 = fromFile "/home/sibi/tax.md"

bigF
  :: (MonadResource m)
  => StreamT m ByteString
bigF = fromFile "/home/sibi/Downloads/sample.pdf"

main :: IO ()
main = do
  xs <- runResourceT $ toFile "/home/sibi/jim.pdf" bigF
  print xs
