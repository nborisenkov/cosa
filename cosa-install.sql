-- MySQL dump 10.13  Distrib 5.1.63, for debian-linux-gnu (i486)
--
-- Host: localhost    Database: cosa
-- ------------------------------------------------------
-- Server version	5.1.63-0+squeeze1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `cosa`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `cosa` /*!40100 DEFAULT CHARACTER SET latin1 */;

USE `cosa`;

--
-- Table structure for table `hosts`
--

DROP TABLE IF EXISTS `hosts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `hosts` (
  `addr` varchar(256) NOT NULL,
  `pass` varchar(32) NOT NULL DEFAULT 'BS',
  `bs` tinyint(1) NOT NULL DEFAULT '1',
  `description` varchar(256) DEFAULT NULL,
  `date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`addr`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

LOCK TABLES `hosts` WRITE;                                                                                                                                                                                                                                                     
/*!40000 ALTER TABLE `hosts` DISABLE KEYS */;                                                                                                                                                                                                                                  
INSERT INTO `hosts` VALUES ('10.10.10.1','BS',1,'test-device','2012-10-26 00:00:00');
/*!40000 ALTER TABLE `hosts` ENABLE KEYS */;                                                                                                                                                                                                                                   
UNLOCK TABLES;

--
-- Table structure for table `params`
--

DROP TABLE IF EXISTS `params`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `params` (
  `name` varchar(64) NOT NULL,
  `sid` varchar(16) NOT NULL,
  `band` int(11) NOT NULL,
  `ver_mint` int(11) NOT NULL,
  `rf_mac` varchar(17) NOT NULL,
  `bitr` int(11) NOT NULL,
  `bitr_max` int(11) NOT NULL,
  `rf_ip` varchar(18) NOT NULL,
  `mimo` tinyint(1) NOT NULL,
  `polling` tinyint(1) NOT NULL,
  `roaming` varchar(1) NOT NULL,
  `rf_ospf_area` int(11) NOT NULL,
  `rf_ospf_auth` varchar(4) NOT NULL,
  `lic` int(11) NOT NULL,
  `lic_type` varchar(16) NOT NULL,
  `ver` varchar(64) NOT NULL,
  `rid` varchar(16) NOT NULL,
  `dist` varchar(16) NOT NULL,
  `pwr` varchar(8) NOT NULL,
  `pwr_max` varchar(8) NOT NULL,
  `freq` int(11) NOT NULL,
  `gps` varchar(21) NOT NULL,
  `sn` int(11) NOT NULL,
  `bs_sn` int(11) NOT NULL,
  `uptime` int(11) NOT NULL,
  `update_time` date NOT NULL,
  PRIMARY KEY (`sn`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2012-10-15 15:38:01
