map-schema
==========

LICENSE:
 Copyright 2012 SwarmPoint LLC. Provided by SwarmPoint LLC as is and without warranty.
 License granted for internal commercial or private use, modification or translation.
 Distribution only under the same license. No right to use to offer a database service.
 Owen Brunette owen@beliefs.com +1-646-461-4401 owenbrunette.com

DESCRIPTION:
A lua script for mysql-proxy which allows mysql workbench to synchronize with
schema names that are different from the name of the model schema

mysql workbench (http://www.mysql.com/downloads/workbench/), an otherwise great tool,
is not able to synchronize with databases using other schema names. This script lets
you run a proxy that intercepts the SQL queries from workbench and swaps the schema
names in the queries and the results as they go back. The workbench deficiency is
documented here: http://bugs.mysql.com/bug.php?id=45533

In the simplest configuration a mysql-proxy is run on the mysql server machine,
listening on port 4040 for mysql workbench. The mysql workbench uses a connection
profile with a default database schema of the physical database it normally connects
to. The port number in the connection profile is modified to 4040. The proxy
is started and the databse synchronization is performed.

*UPDATE THE START FILE
The schema name known to the workbench model is placed in the configuration of the proxy
by editing the 'start' script in this directory and replacing my_model_schema in the
line MAP_SCHEMA_MODEL=my_model_schema*

mysql-proxy needs to be installed either as root or in a user directory if that is
what you need to do in your environment. If you are able to install the package as
root or have an adminsitrator install it then the instructions are at
http://dev.mysql.com/doc/refman/5.6/en/mysql-proxy-install.html

README.md           - This file
install-mysql-proxy - Install mysql-proxy
map-schema.lua      - The script itself
start               - start the proxy, passing it the script.

