#!/bin/bash

# Treat unset variables as an error
set -o nounset

# Source configuration
source $1 || exit 126

echo -e "${BUILD}"

##
# Needed executables & drush commands
#
DRUSH=$(which drush) &> /dev/null \
  || { echo 'Missing drush. Aborting...' >&2; exit 127; } 

# Specific path to drush version for drush site-install
set +o nounset
[ -z "$DRUSH_SITE_INSTALL_DRUSH" ] && DRUSH_SITE_INSTALL_DRUSH=${DRUSH}
set -o nounset

which git &> /dev/null \
  || { echo 'Missing git. Aborting...'>&2; exit 127; }

drush help make &> /dev/null \
  || { echo "Could not probe 'drush make'. Aborting...">&2; exit 127; }

${DRUSH_SITE_INSTALL_DRUSH} help site-install &> /dev/null \
  || { echo "Could not probe 'drush site-install'. Aborting...">&2; exit 127; }


##
# run drush make
#
cd ${WEB_DIR}
echo -e "# Running drush make, create new build ${BUILD} with ${BUILD_MAKEFILE}...\n"
${DRUSH} make ${MAKE_OPTIONS} ${BUILD_MAKEFILE} ${BUILD} 2>&1 \
  && echo -e "\n# Creating build ${BUILD} was successful\n" \
  || { echo -e "\nFAILED 1!\n"; exit 1; }

##
# link new build to docroot
# commenting out below section as we are intended to create a new instance of
# database and codebase of the given profile.
#
if [ -L ${DOC_ROOT} ] ; then
  echo -ne "# Symlink ${BUILD} already exists, unlink ${BUILD}... " 
  unlink ${DOC_ROOT} 2>&1 \
    && echo -e "done\n" \
    || { echo -e  "FAILED 2!\n"; exit 2; }	  
fi
echo -ne "# Symlink ${BUILD} to ${WEB_DIR}/${DOC_ROOT}... "
ln -s ${BUILD} ${DOC_ROOT} 2>&1 \
  && echo -e "done\n" \
  || { echo -e "FAILED 3!\n"; exit 3; }

##
# run drush site-install (and drop existing tables)
# set sendmail path to /usr/bin/true if it is not configured properly.

echo -e "# Running drush site-install...\n"
/usr/bin/env PHP_OPTIONS="-d sendmail_path=`which true`" ${DRUSH_SITE_INSTALL_DRUSH} site-install ${BUILD_PROFILE} ${SI_OPTIONS} -y -r ${WEB_DIR}/${DOC_ROOT} \
 --db-url=${DB_DRIVER}://${DB_USER}:${DB_PASS}@${DB_HOST}/${DB} \
 --account-name=${DRUPAL_UID1} \
 --account-pass=${DRUPAL_UID1_PASS} \
 --site-name=${DRUPAL_SITE_NAME} 2>&1 \
 && echo -e "\n# Site installation was successful." \
 || { echo -e "\n# FAILED 4!"; exit 4; }

# Files directory (local dev)
sudo chmod -R 777 ${FILE_DIR}
sudo chown -R vagrant:vagrant ${BUILD_ROOT}
# Files directory (remote dev/stage/prod)
#sudo chown -R _www:_www /var/www/html/${BUILD}/sites/default/files

##
# Create virtual directory configuration file for this build
#
sudo touch ${CONF}
sudo chmod -R 777 ${CONF}
sudo chown -R vagrant:vagrant ${CONF}
FILE=${CONF}
echo "# ************************************
# Vhost template generated by build script.
# ************************************

<VirtualHost *:80>
  ServerName ${BUILD}.demoserver.com

  ## Vhost docroot
  DocumentRoot "/var/www/html/${BUILD}"

  ## Directories, there should at least be a declaration for /www/rml/current

  <Directory "/var/www/html/${BUILD}">
    Options FollowSymLinks
    AllowOverride all
    Order allow,deny
    Allow from all
  </Directory>

  ## Load additional static includes

  ## Logging
  ErrorLog "/var/log/httpd/${BUILD}.demoserver.com_error_log"
  ServerSignature Off
  CustomLog "/var/log/httpd/${BUILD}.demoserver.com_access_log" "combined1"

  ## Rewrite rules
  RewriteEngine On

  ## Server aliases
  ServerAlias ${BUILD}.demoserver.com

  ## Custom fragment
<IfModule php5_module>
  php_value upload_max_filesize 10M
  php_value post_max_size 10M
</IfModule>

</VirtualHost>" >> $FILE

sudo systemctl restart httpd

##
# write host entry to the windows hosts file. 
#
echo -e "\n# Adding hosts entry to windows hosts file...\n"
FILE=${WIN_HOSTS}
echo "192.168.33.12 ${BUILD}.demoserver.com" >> $FILE
echo -e "\n# Host entry added--\n192.168.33.12 ${BUILD}.demoserver.com\n"

FILE=${BUILD_INFO_DIR}/build-record-existing.txt
echo "${BUILD}" >> $FILE

exit 0 
