module Settings(
    Settings(..)
  , SqlServer(..)
  ) where

import Data.Aeson
import Data.Aeson.QQ
import Data.Text
import GHC.Generics 

data Settings = Settings {
  settingsBindAddresses :: [Text]
, settingsHostname :: Text
, settingsPort :: Int
, settingsMaxConn :: Int
, settingsSqlServers :: [SqlServer]
, settingsSqlTimeout :: Int
, settingsAliveCheckTime :: Int
, settingsSqlReconnectTime :: Int
, settingsSqlAuth :: [Text]
, settingsSqlJsonTable :: Text
, settingsLogname :: Text
, settingsUserid :: Text
, settingsGroupid :: Text
} deriving (Show, Generic)

instance FromJSON Settings where
  parseJSON (Object o) = Settings 
    <$> o .: "bindAddresses"
    <*> o .: "hostname"
    <*> o .: "port"
    <*> o .: "maxConn"
    <*> o .: "sqlServers"
    <*> o .: "sqlTimeout"
    <*> o .: "aliveCheckTime"
    <*> o .: "sqlReconnectTime"
    <*> o .: "sqlAuth"
    <*> o .: "sqlJsonTable"
    <*> o .: "logname"
    <*> o .: "userid"
    <*> o .: "groupid"

  parseJSON _ = fail "Settings expected Object"

instance ToJSON Settings where
  toJSON Settings{..} = [aesonQQ|
    {
      "bindAddresses": #{settingsBindAddresses},
      "hostname": #{settingsHostname},
      "port": #{settingsPort},
      "maxConn": #{settingsMaxConn},
      "sqlServers": #{settingsSqlServers},
      "sqlTimeout": #{settingsSqlTimeout},
      "aliveCheckTime": #{settingsAliveCheckTime},
      "sqlReconnectTime": #{settingsSqlReconnectTime},
      "sqlAuth": #{settingsSqlAuth},
      "sqlJsonTable": #{settingsSqlJsonTable},
      "logname": #{settingsLogname},
      "userid": #{settingsUserid},
      "groupid": #{settingsGroupid}
    }
    |]

data SqlServer = SqlServer {
  sqlServerName :: Text
, sqlServerConnString :: Text
, sqlServerMaxConn :: Int
} deriving (Show, Generic)

instance FromJSON SqlServer where
  parseJSON (Object o) = SqlServer 
    <$> o .: "name"
    <*> o .: "connString"
    <*> o .: "maxConn"
  parseJSON _ = fail "SqlServer expected Object"

instance ToJSON SqlServer where
  toJSON SqlServer{..} = [aesonQQ|
    {
      "name": #{sqlServerName},
      "connString": #{sqlServerConnString},
      "maxConn": #{sqlServerMaxConn}
    }
    |]
