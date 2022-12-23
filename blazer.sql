-- MySQL dump 10.13  Distrib 8.0.31, for Linux (x86_64)
--
-- Host: localhost    Database: IRM_development
-- ------------------------------------------------------
-- Server version	8.0.31-0ubuntu0.20.04.2

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `blazer_queries`
--

DROP TABLE IF EXISTS `blazer_queries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `blazer_queries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `creator_id` bigint DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `description` text,
  `statement` text,
  `data_source` varchar(255) DEFAULT NULL,
  `status` varchar(255) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_blazer_queries_on_creator_id` (`creator_id`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `blazer_queries`
--

LOCK TABLES `blazer_queries` WRITE;
/*!40000 ALTER TABLE `blazer_queries` DISABLE KEYS */;
INSERT INTO `blazer_queries` VALUES (1,NULL,'Users Sign In Count','','SELECT users.id as user_id, users.first_name, users.last_name, users.email, users.created_at, users.sign_in_count, entities.name FROM `users` INNER JOIN `entities` ON `entities`.`deleted_at` IS NULL AND `entities`.`id` = `users`.`entity_id` where entities.name={entity_name}','main','active','2022-12-20 08:34:42.444890','2022-12-20 08:56:39.026074'),(2,NULL,'Users by Company','','SELECT `entities`.`name` AS `entities_name`, COUNT(*) AS `count` FROM `users` INNER JOIN `entities` ON `entities`.`deleted_at` IS NULL AND `entities`.`id` = `users`.`entity_id` and entity_type not in (\'holding, trust\') and entity_type={entity_type} GROUP BY `entities`.`name` ','main','active','2022-12-20 09:05:02.982164','2022-12-20 10:01:43.672000'),(3,NULL,'Companies Created Per Week','Companies Created per week','SELECT EXTRACT(WEEK FROM  created_at) as week, COUNT(*) as company_count FROM entities GROUP BY week\r\n','main','active','2022-12-20 09:33:23.263366','2022-12-20 09:48:08.737091'),(4,NULL,'Entity Types','','select entity_type, count(*) from entities group by 1;','main','active','2022-12-20 09:42:11.264338','2022-12-20 09:42:11.264338'),(5,NULL,'Company Type Pie','','SELECT entity_type, COUNT(*) AS pie FROM entities GROUP BY 1\r\n','main','active','2022-12-20 09:49:39.432082','2022-12-20 09:49:39.432082'),(6,NULL,'Recent Users (2 Weeks), No Sign In','','SELECT users.id as user_id, users.first_name, users.last_name, users.email, users.created_at, users.sign_in_count, entities.name as entity_name FROM `users` INNER JOIN `entities` ON `entities`.`deleted_at` IS NULL AND `entities`.`id` = `users`.`entity_id` WHERE users.sign_in_count = 0 and users.created_at > DATE_SUB(curdate(), INTERVAL 2 WEEK)\r\n /* all ratings should have a user */\r\n','main','active','2022-12-20 09:54:39.314642','2022-12-20 10:04:11.337427'),(7,47,'Company Users','','SELECT users.id as user_id, users.first_name, users.last_name, users.email, users.created_at, users.sign_in_count, entities.name FROM `users` INNER JOIN `entities` ON `entities`.`deleted_at` IS NULL AND `entities`.`id` = `users`.`entity_id` where entities.id={entity_id}','main','active','2022-12-20 20:43:23.440458','2022-12-20 20:44:24.334264'),(8,47,'Company Investors','','SELECT investors.id as investor_id, investors.investor_name, investors.category, investors.city, investors.created_at FROM `investors` INNER JOIN `entities` ON `entities`.`deleted_at` IS NULL AND `entities`.`id` = `investors`.`entity_id` and entity_type not in (\'holding, trust\') and entities.id={entity_id}','main','active','2022-12-20 20:46:15.192300','2022-12-20 20:47:52.632278'),(9,47,'Company Latest Documents','','SELECT documents.id as document_id, documents.name, documents.created_at FROM `documents` INNER JOIN `entities` ON `entities`.`deleted_at` IS NULL AND `entities`.`id` = `documents`.`entity_id` and  entities.id={entity_id} order by documents.created_at desc limit 5','main','active','2022-12-20 20:51:09.466256','2022-12-21 09:50:58.064754'),(10,47,'Company Deals','','SELECT deals.id as deal_id, deals.name, deals.status, deals.start_date, deals.created_at FROM `deals` INNER JOIN `entities` ON `entities`.`deleted_at` IS NULL AND `entities`.`id` = `deals`.`entity_id` and entity_type not in (\'holding, trust\') and entities.id={entity_id}','main','active','2022-12-21 09:55:05.308928','2022-12-21 09:55:05.308928'),(11,47,'Company Secondaries','','SELECT secondary_sales.id as secondary_sale_id, secondary_sales.name, secondary_sales.end_date, secondary_sales.percent_allowed, secondary_sales.created_at FROM `secondary_sales` INNER JOIN `entities` ON `entities`.`deleted_at` IS NULL AND `entities`.`id` = `secondary_sales`.`entity_id` and entity_type not in (\'holding\') and entities.id={entity_id}','main','active','2022-12-21 10:04:37.085976','2022-12-21 10:07:22.759841');
/*!40000 ALTER TABLE `blazer_queries` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `blazer_dashboards`
--

DROP TABLE IF EXISTS `blazer_dashboards`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `blazer_dashboards` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `creator_id` bigint DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_blazer_dashboards_on_creator_id` (`creator_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `blazer_dashboards`
--

LOCK TABLES `blazer_dashboards` WRITE;
/*!40000 ALTER TABLE `blazer_dashboards` DISABLE KEYS */;
INSERT INTO `blazer_dashboards` VALUES (1,NULL,'Users & Entities','2022-12-20 08:35:24.918301','2022-12-20 09:57:36.867009'),(2,47,'Company Dashboard','2022-12-20 20:48:59.462375','2022-12-20 20:48:59.462375');
/*!40000 ALTER TABLE `blazer_dashboards` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `blazer_dashboard_queries`
--

DROP TABLE IF EXISTS `blazer_dashboard_queries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `blazer_dashboard_queries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `dashboard_id` bigint DEFAULT NULL,
  `query_id` bigint DEFAULT NULL,
  `position` int DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_blazer_dashboard_queries_on_dashboard_id` (`dashboard_id`),
  KEY `index_blazer_dashboard_queries_on_query_id` (`query_id`)
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `blazer_dashboard_queries`
--

LOCK TABLES `blazer_dashboard_queries` WRITE;
/*!40000 ALTER TABLE `blazer_dashboard_queries` DISABLE KEYS */;
INSERT INTO `blazer_dashboard_queries` VALUES (4,1,3,1,'2022-12-20 09:42:37.141234','2022-12-20 10:03:37.967222'),(5,1,5,2,'2022-12-20 09:49:51.592162','2022-12-20 10:03:37.977424'),(6,1,6,0,'2022-12-20 09:57:36.881976','2022-12-20 10:03:17.535188'),(7,1,4,3,'2022-12-20 10:03:37.987938','2022-12-20 10:03:37.987938'),(8,2,8,0,'2022-12-20 20:48:59.480073','2022-12-20 20:48:59.480073'),(9,2,7,1,'2022-12-20 20:48:59.491209','2022-12-20 20:48:59.491209'),(10,2,9,2,'2022-12-21 09:51:27.548330','2022-12-21 09:51:27.548330'),(11,2,10,3,'2022-12-21 09:56:38.834022','2022-12-21 09:56:38.834022'),(12,2,11,4,'2022-12-21 10:07:35.488262','2022-12-21 10:07:35.488262');
/*!40000 ALTER TABLE `blazer_dashboard_queries` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `blazer_checks`
--

DROP TABLE IF EXISTS `blazer_checks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `blazer_checks` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `creator_id` bigint DEFAULT NULL,
  `query_id` bigint DEFAULT NULL,
  `state` varchar(255) DEFAULT NULL,
  `schedule` varchar(255) DEFAULT NULL,
  `emails` text,
  `slack_channels` text,
  `check_type` varchar(255) DEFAULT NULL,
  `message` text,
  `last_run_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_blazer_checks_on_creator_id` (`creator_id`),
  KEY `index_blazer_checks_on_query_id` (`query_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `blazer_checks`
--

LOCK TABLES `blazer_checks` WRITE;
/*!40000 ALTER TABLE `blazer_checks` DISABLE KEYS */;
INSERT INTO `blazer_checks` VALUES (1,NULL,6,'failing','1 day','thimmaiah@gmail.com',NULL,'bad_data',NULL,'2022-12-21 10:17:00.579729','2022-12-20 09:55:02.415661','2022-12-21 10:17:00.583091');
/*!40000 ALTER TABLE `blazer_checks` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2022-12-21 10:26:11
