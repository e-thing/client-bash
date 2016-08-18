ething&#46;sh
=========

A linux command line e-Thing client. Use it to access your data stored in your e-Thing server.


## usage :

```bash
ething.sh [global options] <command> [command args]
```

> Most of the commands return JSON data.

## global options :


Option            | Description
---               | ---    
`-h`, `--help`    | This help message
`-d`, `--debug`   | Enable debugging messages (implies verbose)
`-v`, `--verbose` | Enable verbose messages
`-u`, `--api-url` | Define the url of the EThing API to access to (default to http://localhost/ething/api/v1)
`-k`, `--api-key` | Define the API key for this request
`--token`         | Define the token for this request
`--user`          | auth user
`--password`      | auth password


## Authentication :

You need to authenticate yourself to your e-Thing Server before you perform any operations. You can authenticated either as a device (using an API key) : 

```bash
ething.sh --api-key fdd72e89-38b8-4069-a65a-e2f8e1aedcf6 ...
```

or as an user (by providing your credentials) :

```bash
ething.sh --user john --password secret ...
```


## Available commands :

### connect

  This command allows you to start a new session and save it for further requests.

> **Note:** The session is valid only for a certain amount of time !

example :

```bash
ething.sh --user john --password secret --api-url http://192.168.1.112/ething/api/v1 connect

# you do not need to specify the credentials for the next commands
ething.sh list
```

### usage

  This command allows you to get information about the space usage.

### profile

  This command allows you to get information about your profile.

### list

  This command allows you to list resources.

Option           | Description
---              | ---    
`-q`, `--query`  | Query string for searching resources
`--limit`        | Limits the number of resources returned
`--skip`         | Skips a number of resources 
`--sort`         | The key on which to do the sorting, by default the sort is made by modifiedDate descending. To make the sort descending, prepend the field name by minus '-'. For instance, '-createdDate' will sort by createdDate descending
`--fields`       | Only this fields will be returned (comma separated values)

example :

```bash
ething.sh list --fields id,name,type,modifiedDate

# list only files :
ething.sh list --query "type=='File'"
```

### get

  This command allows you to download resources.

usage :

```bash
ething.sh [global options] get [command options] resource...
```

Option           | Description
---              | ---    
`-f`, `--format` |    the output format (default to JSON) **[only for table]**
`-q`, `--query`  |    Query string for filtering results **[only for table]**
`--sort`         |    the key on which to do the sorting, by default the sort is made by date ascending. To make the sort descending, prepend the field name by minus '-'. For instance, '-date' will sort by date descending **[only for table]**
`--start`        |      Position of the first rows to return. If start is negative, the position will start from the end. (default to 0) **[only for table]**
`--length`       |     Maximum number of rows to return. If not set, returns until the end. **[only for table]**
`--fields`       |      Only this fields will be returned (comma separated values) **[only for table]**


exemple :

```bash
# download a file from its name :
ething.sh get file.txt

# download from its id :
ething.sh get 40XTGKr

# returns only the first 10 records of a table :
ething.sh get --length 10 table.db
```

> **Note:** Multiple resources may have the same name. So by passing names instead of ids, only the first resource that match the name will be downloaded.


### put

  This command allows you to upload files.

usage :

```bash
ething.sh [global options] put localFile...
```

example :

```bash
ething.sh put file.txt
```
