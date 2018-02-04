module Main where

import Lib
import Streamly.ByteString
import Streamly
import Data.ByteString

-- import Streamly.Prelude (toHandle)
import qualified System.IO as IO

echo = toHandle IO.stdout (stdin :: StreamT IO ByteString)

main :: IO ()
main = echo
