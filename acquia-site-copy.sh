#!/bin/bash

###############################################################
#               Acquia Site Server Copy Utility               #
#               Author: phi.vanngoc@activearkjwt.com          #
###############################################################

VERSION=0.1
REPOS_URL=http://104.131.99.199/acquia-site-copy.sh
INSTALL_PATH=/usr/local/bin/acquia-site-copy

SITE_NAME=""
ENVIRONMENT=""
OPTION=""
LOCAL_DOCROOT=""
MULTISITE=""
LOCAL_SITE_URL=""
SITE_URL=""
SUB_SITE_NAME=""
SERVER_URL_SUFFIX=""
SERVER_NAME=""
SERVER_URL=""
SYNC_FILE_METHOD=proxy


PARAMS_CACHE_DIR=$HOME/.acquia-site-copy
SCRIPT_NAME="$0"


# Results of oprations
DB_UPDATE_RET=1
FILE_UPDATE_RET=0

# Some global variables
CHOSEN_CACHE_FILE=""


# Reset
txtOff='\e[0m'          # Text Reset
txtBlack='\e[0;30m'     # Black - Regular
txtRed='\e[0;31m'       # Red
txtGreen='\e[0;32m'     # Green
txtYellow='\e[0;33m'    # Yellow
txtBlue='\e[0;34m'      # Blue
txtPurple='\e[0;35m'    # Purple
txtCyan='\e[0;36m'      # Cyan
txtWhite='\e[0;37m'     # White

# Get default local webroot
script="$(readlink -f ${BASH_SOURCE[0]})"
base="$(dirname $script)"

cd $base && cd ..
LOCAL_DOCROOT=$(pwd)/docroot

[ ! -d "$LOCAL_DOCROOT" ] && LOCAL_DOCROOT=""

__print_usage()
{
  echo "Usage:"
  echo -e "\t$0 -o [option] -e [stg|prod] -h [server url] -s [site name] -d [database name]"
  echo
  echo "Options:"
  echo -e "\t- all: Update both database & files"
  echo -e "\t- db: Update only database"
  echo -e "\t- file: Update only files"

  echo "Servers:"
  echo -e "\t- stg: Staging server"
  echo -e "\t- prod: Production server"
  echo
  echo -e "If no path to local webroot is specified, default to $LOCAL_DOCROOT"
  echo -e "If no server is specified, default to staging server"
  echo
  echo "Example:"
  echo -e "\t$0 db /var/www/newnokia.local"
}

__get_server_name()
{
  if [ -z "$SERVER_NAME" ]; then
    while [ -z "$SERVER_NAME" ]; do
      __print_prompt "Acquia server name without .prod.hosting.acquia.com (for example, staging-4605): "
      read SERVER_NAME
    done
  else
    __print_prompt "Acquia server name without .prod.hosting.acquia.com (for example, staging-4605): "
    read SERVER_NAME
  fi

  [ ! -z "$SERVER_NAME" ] && [ ! -z "$SERVER_URL_SUFFIX" ] && SERVER_URL=${SERVER_NAME}.${SERVER_URL_SUFFIX}
}


__get_server_url_suffix()
{
  local suffices=("prod.hosting.acquia.com" "devcloud.hosting.acquia.com") suffix
  select SERVER_URL_SUFFIX in "${suffices[@]}"; do
    case $REPLY in
      1|2)
        break
        ;;
      *)
        __print_error "Invalid selection. Please try again!"
        ;;
    esac
  done

  [ ! -z "$SERVER_NAME" ] && [ ! -z "$SERVER_URL_SUFFIX" ] && SERVER_URL=${SERVER_NAME}.${SERVER_URL_SUFFIX}
}


__check_server_is_live()
{
  ping -c 1 $SERVER_URL >/dev/null 2>&1
  echo $?
}


__do_self_update()
{
  sudo mv $1 $INSTALL_PATH; [ -f $INSTALL_PATH ]; sudo chmod a+x $INSTALL_PATH; local status=$?
  __print_command_status "Self update"
  [ $status -eq 0 ] && __print_info "You need to relaunch the script, quit now!" && exit
}

__get_new_version()
{
  local tmp_file="/tmp/acquia-site-copy_$(date +%Y_%m_%d_%H_%M).sh" answer
  curl -o $tmp_file $REPOS_URL 2>/dev/null

  if [ -f $tmp_file ]; then
    local version=$(egrep "VERSION=[0-9\.]+" $tmp_file)
    version=${version#VERSION=}
    [ ! -z "$version" ] && [ "$version" != "$VERSION" ] &&  echo $tmp_file || echo ""
  else
    echo ""
  fi
}


__check_update_requirements()
{
  which curl >/dev/null 2>&1
  return $?
}

__confirm_update()
{
  echo -e -n "${txtGreen}UPDATE:${txtOff} ${txtYellow}There is a new version of the script, do you want to update it now?${txtOff} [y/n] "
  read answer

  case $answer in
    y|Y)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}


__check_update()
{
  __check_update_requirements
  local req_status=$?

  [ ! $? -eq 0 ] && [ "$1" == "verbose" ] && __print_error "You dont have curl installed. Please install it first." && exit 1
  [ ! $req_status -eq 0 ] && [ "$1" != "verbose" ] && return 1

  local new_version=$(__get_new_version)
  if [ ! -z "$new_version" ]; then
    __confirm_update && __do_self_update $new_version || [ "$1" == "verbose" ] && exit
  else
    [ "$1" == "verbose" ] && __print_warning "No update available" && exit
  fi
}

__get_copy_option()
{
  __print_info "What top copy:"
  options=("database" "file" "all")

  select OPTION in ${options[@]}; do
    case $OPTION in
      database|file|all)
        break
        ;;
      *)
        __print_error "Invalid option. Please try again!"
        ;;
    esac
  done
}


__get_environment()
{
  __print_info "Environment to copy from:"
  envs=("dev" "stg" "prod")

  select ENVIRONMENT in ${envs[@]}; do
    case $ENVIRONMENT in
      dev|stg|prod)
        break;
        ;;
      *)
        __print_error "Invalid option. Please try again!"
        ;;
    esac
  done

  # Change stg to test as Acquia is not using stg for drush alias
  [ "$ENVIRONMENT" == "stg" ] && ENVIRONMENT=test
}


__get_site_name()
{
  while [ "$SITE_NAME" == "" ]; do
    __print_prompt "Name of the site (Acquia site name): "
    read SITE_NAME
  done
}


__get_multisite()
{
  __print_prompt "Is the site multisite" "[y/n]"
  read MULTISITE

  if [ "$MULTISITE" != "y" -a "$MULTISITE" != "n" ]; then
    MULTISITE="n"
  fi 
  
  if [ "$MULTISITE" == "y" ]; then
    [ -z "$SITE_URL" ] && __get_site_url
    [ -z "$LOCAL_SITE_URL" ] && __get_local_site_url
    [ -z "$SUB_SITE_NAME" ] && __get_sub_site_name
  fi
}

__get_local_docroot()
{
  __print_prompt "Local site docroot path: "
  read LOCAL_DOCROOT
}

__get_local_site_url()
{
  __print_prompt "Local site URL: "
  read LOCAL_SITE_URL
}

__get_site_url()
{
  __print_prompt "Remote site URL: "
  read SITE_URL
}

__get_sub_site_name()
{
  __print_prompt "Name of the subsite in the multisite setup: "
  read SUB_SITE_NAME
}

__print_error()
{
  echo -e "${txtRed}$1${txtOff}"
}

__print_info()
{
  echo -e "${txtGreen}$1${txtOff}"
}

__print_prompt()
{
  echo -e -n "${txtGreen}$1${txtOff} $2"
}

__print_warning()
{
  echo -e "${txtYellow}$1${txtOff}"
}

__prompt_user_input()
{
  local answer
  read -p "$1" answer
  echo $answer
}

__print_command_status()
{
  if [ $? -eq 0 ]; then
    echo -e "${txtGreen}$1: ${txtOff}[ OK ]"
  else
    echo -e "${txtGreen}$1: ${txtOff}[${txtRed} ERROR ${txtOff}]"
  fi
}

__get_sync_file_method()
{
  __print_info "Select file syncing method:"

  local methods=("download" "proxy")
  select SYNC_FILE_METHOD in ${methods[@]}; do
    case $SYNC_FILE_METHOD in
      download|proxy)
        break
        ;;
      *)
        __print_error "Wrong method. Please try again!"
        ;;
    esac
  done
}

# Parse the command arguments and/or ask users for necessary options
__get_options()
{
  while getopts "o:e:h:s:l:r:m:t:z" opt; do
    case "$opt" in
      o)
        OPTION=$OPTARG ;;
      e)
        ENVIRONMENT=$OPTARG ;;
      h)
        SERVER_NAME=$OPTARG ;;
      s)
        SITE_NAME=$OPTARG ;;
      r)
        LOCAL_DOCROOT=$OPTARG ;;
      m)
        MULTISITE=$OPTARG ;;
      l)
        LOCAL_SITE_URL=$OPTARG ;;
      t)
        SITE_URL=$OPTARG ;;
      z)
        SUB_SITE_NAME=$OPTARG ;;
    esac
  done

  [ -z "$SITE_NAME" ] && __get_site_name
  [ -z "$ENVIRONMENT" ] && __get_environment

  __confirm_existing

  [ -z "$SERVER_NAME" ] && __get_server_name
  [ -z "$SERVER_URL_SUFFIX" ] && __get_server_url_suffix
  [ -z "$OPTION" ] && __get_copy_option
  [ -z "$LOCAL_DOCROOT" ] && __get_local_docroot
  [ -z "$MULTISITE" ] && __get_multisite

  if [ "$MULTISITE" == "y" ]; then
    [ -z "$SITE_URL" ] && __get_site_url
    [ -z "$LOCAL_SITE_URL" ] && __get_local_site_url
    [ -z "$SUB_SITE_NAME" ] && __get_sub_site_name
  fi

  if [ "$OPTION" == "all" -o "$OPTION" == "file" ]; then
    [ -z "$SYNC_FILE_METHOD" ] && __get_sync_file_method
  fi
}

__get_param_cache_file()
{
  echo "$PARAMS_CACHE_DIR/$SITE_NAME-$ENVIRONMENT"
}

__confirm_existing()
{
  local cache_file=$(__get_param_cache_file)

  if [ -f "$cache_file" ]; then
    params=$(cat $cache_file)

    if [ ! -z "$params" ]; then
      __print_info "Reuse following params in the cache"
      source $cache_file
    fi
  fi
}


__confirm_options()
{
  local quit="" index i=1
  local labels values

  labels[1]="Server name"
  labels[2]="Environment"
  labels[3]="What to copy"
  labels[4]="Site name"
  labels[5]="Multisite"
  labels[6]="Subsite name"
  labels[7]="Remote site URL"
  labels[8]="Local site URL"
  labels[9]="Local docroot"
  labels[10]="Sync file method"
  labels[11]="Server URL suffix"

  while [ -z "$quit" ]; do
    __print_info "Enter the number of your choice to modify the information"

    values[1]="$SERVER_NAME"
    values[2]="$ENVIRONMENT"
    values[3]="$OPTION"
    values[4]="$SITE_NAME"
    values[5]="$MULTISITE"
    values[6]="$SUB_SITE_NAME"
    values[7]="$SITE_URL"
    values[8]="$LOCAL_SITE_URL"
    values[9]="$LOCAL_DOCROOT"
    values[10]="$SYNC_FILE_METHOD"
    values[11]="$SERVER_URL_SUFFIX"

    for (( i=1; i<=${#labels[@]}; i++ )); do
      echo -e "${i}) ${txtYellow}${labels[$i]}${txtOff}: ${txtWhite}${values[$i]}${txtOff}"
    done

    __print_prompt "Your choice [Accept]:"
    read index

    case $index in
      1)
        __get_server_name
        ;;
      2)
        __get_environment
        ;;
      3)
        __get_copy_option
        ;;
      4)
        __get_site_name
        ;;
      5|6|7|8)
        __get_multisite
        ;;
      9)
        __get_local_docroot
        ;;
      10)
        __get_sync_file_method
        ;;
      11)
        __get_server_url_suffix
        ;;
      *)
        quit=yes
        ;;
    esac
  done
}


__issue_ssh_drush_command()
{
  ssh ${SITE_NAME}.${ENVIRONMENT}@$SERVER_URL "$1"
}


__issue_local_drush_command()
{
  local multisite_opt_local=$(__get_drush_multisite_opt)
  drush $multisite_opt_local $1 >/dev/null 2>&1
  return $?
}


# Dump the remote database and update local one
__update_database()
{
  if [ ! "$(__check_server_is_live)" -eq 0 ]; then
    __print_error "Can not access server at ${SERVER_URL}. Please check that server name & suffix are correct"
    return 1
  fi

  local db_file=db_backup_${SITE_NAME}_${ENVIRONMENT}_$(date +%Y_%m_%d_%H_%M).sql
  local multisite_opt_remote=$(__get_drush_multisite_opt $SITE_URL)
  local multisite_opt_local=$(__get_drush_multisite_opt)
  local import_status=1

  __print_info "Generate database snapshot on server $SERVER_URL. This may take a while"

  # Dump the remote database
  __issue_ssh_drush_command "drush @${SITE_NAME}.${ENVIRONMENT} sql-dump $multisite_opt_remote --gzip > /tmp/$db_file.gz"

  # Copy the database dump to local
  __print_info "Copy remote database dump to local"
  scp $SITE_NAME@$SERVER_URL:/tmp/$db_file.gz /tmp/

  # Unzip the database dump file 
  cd /tmp; gunzip $db_file.gz >/dev/null 2>&1; DB_UPDATE_RET=$?
  __print_command_status "Unzip database dump"

  # Only proceed if the command succeeds. Otherwise, we may drop the local database totally.
  if [ $DB_UPDATE_RET -eq 0 ]; then

    cd $LOCAL_DOCROOT
    local db_backup=local_db_backup_${SITE_NAME}_$(date +%Y_%m_%d_%H_%M).sql


    if [ -f /tmp/$db_file ]; then
      __print_command_status "Make a backup of local database (/tmp/$db_backup)" $(drush $multisite_opt_local sql-dump > /tmp/$db_backup 2>&1)

      __print_command_status "Drop all local database tables" $(__issue_local_drush_command "sql-drop --yes")

      drush $multisite_opt_local sql-cli < /tmp/$db_file; import_status=$?
      __print_command_status "Import remote database dump"

      __print_command_status "Remove temporary database dump files on local" $(rm -f /tmp/$db_file.gz; rm -f /tmp/$db_file)

      __print_command_status "Remove temporary database dump files on server" $(ssh $SITE_NAME@$SERVER_URL "cd /tmp; rm -f $db_file.gz")

      if [ $import_status -eq 0 ]; then
        __post_database_update
        __restart_memcache
      fi
    else
      __print_error "Database dump file is corrupted. No action done"
    fi

  else
    __print_error "Remote database dump is invalid. Please check your settings"
  fi
}

__print_banner()
{
  echo
  echo -e "${txtWhite}\e[44m###########################################${txtOff}"
  echo -e "${txtWhite}\e[44m#         ACQUIA SITE COPY UTILITY        #${txtOff}"
  echo -e "${txtWhite}\e[44m###########################################${txtOff}"
  echo
}


__print_footer()
{
  __print_warning "DONE!"
}

__put_site_offline()
{
  cd $LOCAL_DOCROOT
  __print_command_status "Put site into maintenance mode" $(__issue_local_drush_command "vset maintenance_mode 1")
}


__get_drush_multisite_opt()
{
  local multisite_opt=""

  if [ "$MULTISITE" == "y" ]; then
    local uri=$LOCAL_SITE_URL

    if [ $# -eq 1 ]; then
      uri=$1
    fi
    multisite_opt="--uri=$uri"
  fi

  echo $multisite_opt
}


# This only needs to be run when database update succeeds
__post_database_update()
{
  cd $LOCAL_DOCROOT
  __print_command_status "Enable Devel module" $(__issue_local_drush_command "en --yes devel")

  __print_command_status "Enable Views UI module" $(__issue_local_drush_command "en --yes views_ui")

  __print_command_status "Disable Securepages module" $(__issue_local_drush_command "vset securepages_enable --exact 0")

  __print_command_status "Disable Shield module" $(__issue_local_drush_command "dis --yes shield")

  __print_command_status "Disable CSS caching" $(__issue_local_drush_command "vset preprocess_css 0 --exact --yes")

  __print_command_status "Disable JS caching" $(__issue_local_drush_command "vset preprocess_js 0 --exact --yes")

  __print_command_status "Disable page caching" $(__issue_local_drush_command "vset cache 0 --exact --yes")

  # Remove FirePHPCore downloaded by devel module
  [ -d $LOCAL_DOCROOT/FirePHPCore ] && rm -r $LOCAL_DOCROOT/FirePHPCore
}

__put_site_online()
{
  cd $LOCAL_DOCROOT
  __print_command_status "Put site back to online" $(__issue_local_drush_command "vset maintenance_mode --exact 0")
}

__restart_memcache()
{
  local os=$(__get_os)

  if [ "$os" == "linux" ]; then
    __print_command_status "Restart memcached" $(sudo service memcached restart >/dev/null 2>&1)
  fi
}

__clear_cache()
{
  __print_command_status "Clear all cache" $(__issue_local_drush_command "cache-clear all")
}


__get_os()
{
  echo $(uname) | tr '[:upper:]' '[:lower:]'
}


__sync_files_download()
{
  if [ ! $(__check_server_is_live) -eq 0 ]; then
    __print_error "Can not access server at ${SERVER_URL}. Please check that server name & suffix are correct"
    return 1
  fi

  local server_files_folder=/mnt/files/${SITE_NAME}.${ENVIRONMENT}/sites/default
  __print_info "Sync files with remote server"

  if [ "$MULTISITE" == "y" ]; then
    server_files_folder=/mnt/files/$SITE_NAME.${ENVIRONMENT}/sites/$SUB_SITE_NAME
    rsync -azvv -e ssh $SITE_NAME@$SERVER_URL:$server_files_folder/files $LOCAL_DOCROOT/sites/$SUB_SITE_NAME
  else
    rsync -azvv -e ssh $SITE_NAME@$SERVER_URL:$server_files_folder/files $LOCAL_DOCROOT/sites/default
  fi
}


# Sync file using rsync which would be faster than copying all the files
__sync_files()
{
  if [ "$SYNC_FILE_METHOD" == "download" ]; then
    __sync_files_download
  else
    __sync_files_stage_proxy
  fi

  # Assume that file sync always succeeds
  FILE_UPDATE_RET=0
}


__get_operations_result()
{
  local ret=1

  if [ "$OPTION" == "database" -o "$OPTION" == "all" ]; then
    [ $DB_UPDATE_RET -eq 0 -a $FILE_UPDATE_RET -eq 0 ] && ret=0
  elif [ "$OPTION" == "file" ]; then
    [ $FILE_UPDATE_RET -eq 0 ] && ret=0
  fi

  echo $ret
}

__sync_files_stage_proxy()
{
  if [ -z "$SITE_URL" ]; then
    __get_site_url
  fi
  local multisite_opt=$(__get_drush_multisite_opt)

  cd $LOCAL_DOCROOT
  __print_command_status "Enable stage_file_proxy module" $(__issue_local_drush_command "en -y stage_file_proxy")
  __print_command_status "Set stage_file_proxy_origin" $(__issue_local_drush_command "vset stage_file_proxy_origin $SITE_URL")
}

__save_params()
{
  [ ! -d $PARAMS_CACHE_DIR ] && mkdir $PARAMS_CACHE_DIR
  local cache_file=$(__get_param_cache_file)
  [ ! -f $cache_file ] && touch $cache_file

  if [ -f $cache_file ]; then
    echo "#!/bin/bash" > $cache_file
    echo "SITE_NAME=$SITE_NAME" >> $cache_file
    echo "ENVIRONMENT=$ENVIRONMENT" >> $cache_file
    echo "OPTION=$OPTION" >> $cache_file
    echo "SERVER_NAME=$SERVER_NAME" >> $cache_file
    echo "SERVER_URL_SUFFIX=$SERVER_URL_SUFFIX" >> $cache_file
    echo "SERVER_URL=${SERVER_NAME}.${SERVER_URL_SUFFIX}" >> $cache_file
    echo "SITE_NAME=$SITE_NAME" >> $cache_file
    echo "MULTISITE=$MULTISITE" >> $cache_file
    echo "LOCAL_SITE_URL=$LOCAL_SITE_URL" >> $cache_file
    echo "SITE_URL=$SITE_URL" >> $cache_file
    echo "SUB_SITE_NAME=$SUB_SITE_NAME" >> $cache_file
    echo "LOCAL_DOCROOT=$LOCAL_DOCROOT" >> $cache_file
    echo "SYNC_FILE_METHOD=$SYNC_FILE_METHOD" >> $cache_file
  fi
}


__list_cache_files()
{
  CHOSEN_CACHE_FILE=""

  local files i=1 j choice
  __print_info $1

  for file in $(ls $PARAMS_CACHE_DIR); do
    files[$i]="$file"
    let "i+=1"
  done

  for(( j=1; j<=${#files[@]}; j++ )); do
    echo -e "${j}) ${txtYellow}${files[$j]}${txtOff}"
  done

  __print_prompt "Your choice:"
  read choice

  if [ -f $PARAMS_CACHE_DIR/${files[$choice]} ]; then
    # Have to assign to global variable since we can't use read command when reading 
    # return value from a function.
    CHOSEN_CACHE_FILE="$PARAMS_CACHE_DIR/${files[$choice]}"
  fi
}

__remove_cache()
{
  __list_cache_files "Remove cache file"

  if [ ! -z "$CHOSEN_CACHE_FILE" ] && [ -f $CHOSEN_CACHE_FILE ]; then
    rm "$CHOSEN_CACHE_FILE"
    [ $? -eq 0 ] && __print_info "File removed" || __print_error "Failed to remove file"
  else
    __print_error "Invalid option. Aborted!"
    exit 1
  fi
}


__reuse_cache()
{
  __list_cache_files "Import using cache file"
  if [ ! -z "$CHOSEN_CACHE_FILE" ] && [ -f $CHOSEN_CACHE_FILE ]; then
    source $CHOSEN_CACHE_FILE
  else
    __print_error "Invalid option. Aborted!"
    exit 1
  fi
}

__cache_operations()
{
  local operations=("Remove site" "Import site" "Nothing (quit)") opt
  __print_info "\nWhat do you want to do with cache files?"

  select opt in "${operations[@]}"; do
    case $REPLY in
      1)
        __remove_cache
        exit 0
        ;;

      2)
        __reuse_cache
        break
        ;;

      3|*)
        exit 0
        ;;
    esac
  done
}

__print_cached_database()
{
  if [ -d $PARAMS_CACHE_DIR ] && [ ! -z "$(ls $PARAMS_CACHE_DIR)" ]; then
    cd $PARAMS_CACHE_DIR
    local labels values

    labels[1]="Server name"
    labels[2]="Environment"
    labels[3]="What to copy"
    labels[4]="Site name"
    labels[5]="Multisite"
    labels[6]="Subsite name"
    labels[7]="Remote site URL"
    labels[8]="Local site URL"
    labels[9]="Local docroot"
    labels[10]="Sync file method"
    labels[11]="Server URL suffix"

    for file in $(ls $PARAMS_CACHE_DIR); do
      source $file

      values[1]="$SERVER_NAME"
      values[2]="$ENVIRONMENT"
      values[3]="$OPTION"
      values[4]="$SITE_NAME"
      values[5]="$MULTISITE"
      values[6]="$SUB_SITE_NAME"
      values[7]="$SITE_URL"
      values[8]="$LOCAL_SITE_URL"
      values[9]="$LOCAL_DOCROOT"
      values[10]="$SYNC_FILE_METHOD"
      values[11]="$SERVER_URL_SUFFIX"

      __print_info "\n$file"

      for (( i=1; i<=${#labels[@]}; i++ )); do
        echo -e "${i}) ${txtYellow}${labels[$i]}${txtOff}: ${txtWhite}${values[$i]}${txtOff}"
      done
    done

    __cache_operations
  else
    __print_warning "There is no files in the cache"
    exit 1
  fi
}


__print_current_version()
{
  echo "Current version: $VERSION" && exit 0
}

__print_banner

if [ $# -eq 1 ]; then
  case "$1" in
    --help|-help)
      __print_usage
      exit 0
      ;;

    --cache|-cache)
      __print_cached_database
      ;;

    --update|-update)
      __check_update verbose
      ;;

    --version|-version)
      __print_current_version
      ;;

    *) 
      if [ -f $PARAMS_CACHE_DIR/$1 ]; then
        source $PARAMS_CACHE_DIR/$1
      else
        __print_error "Unknown parameter. Aborted!"
        exit 1
      fi
      ;;
  esac
else
  __check_update
  __get_options "$@"
fi

__confirm_options

echo -e -n "${txtRed}\e[5mWARNING${txtOff}: ${txtYellow}This operation will erase your local database and/or files. Do you want to continue?${txtOff} [y/n] "
read confirm

if [ "$confirm" == "y" -o "$confirm" == "Y" ]; then
  __put_site_offline

  case "$OPTION" in
    database)
      __update_database
      ;;
    file)
      __sync_files
      ;;
    all)
      __update_database
      __sync_files
      ;;
  esac

  if [ $(__get_operations_result) -eq 0 ]; then
    __save_params
  fi

  __put_site_online
  __clear_cache
  __print_footer
fi
