# Use case

You want to replace some characters in a smaller files (f.e. text file) within an Azure Data Factory pipeline.

# Setup

 1. Deploy a Storage Account 
    1. Create a blob container called ``mydata`` 
 1. Deploy an Azure Function with Python
    1. Enable system-assigned managed identity on the azure function
    1. Go to configuration
    1. Create a new application setting called ``STORAGECONNECTION__blobServiceUri`` with value ``https://NAME-OF-YOUR-STORAGE-ACCOUNT.blob.core.windows.net``
    1. Got to functions and create an HTTP Trigger called ``RegexReplaceFile``
    1. click on ``RegexReplaceFile`` and then on Code + Test
    1. Replace all content on the ``__init__.py`` file with below code:
       ```python
       import logging

       import azure.functions as func

       import re

       """
       use query parameter "name" or a body json like this:
       {
           "name": "myfile.txt"
       }
       """

       def main(req: func.HttpRequest, inputBlob: bytes, outputBlob: func.Out[bytes]) -> func.HttpResponse:
           logging.info('Python HTTP trigger function processed a request.')

           name = req.params.get('name')
           if not name:
               try:
                   req_body = req.get_json()
               except ValueError:
                   pass
               else:
                   name = req_body.get('name')

           l1 = len(inputBlob)

           s = re.sub(r'Â', '', inputBlob)
           outputBlob.set(s)

           l2 = len(s)

           return func.HttpResponse(f"Processed file {name}.\nWe have read {l1} bytes and written {l2} bytes!\nContent:\n{s}")
       ```
    1. Replace all content on the ``function.json`` file with below configuration:
       ```json
       {
            "bindings": [
                {
                    "authLevel": "function",
                    "type": "httpTrigger",
                    "direction": "in",
                    "name": "req",
                    "methods": [
                        "get",
                        "post"
                    ]
                },
                {
                    "type": "http",
                    "direction": "out",
                    "name": "$return"
                },
                {
                    "name": "inputBlob",
                    "direction": "in",
                    "type": "blob",
                    "path": "mydata/{name}",
                    "connection": "STORAGECONNECTION"
                },
                {
                    "name": "outputBlob",
                    "direction": "out",
                    "type": "blob",
                    "path": "mydata/{name}",
                    "connection": "STORAGECONNECTION"
                }
            ]
       }
       ``` 
 1. Go to the storage account and give ``Storage Blob Data Owner`` to the function, that you have created
 1. Deploy a Data Factory
    1. Create a new pipeline called ``function_py_call``
    1. Add an Azure Function Activity
       1. Under General
          | Field          | Value                       |
          |----------------|-----------------------------|
          | Name           | RegexReplaceFile Call       |

       1. Under Settings
          | Field          | Value                       |
          |----------------|-----------------------------|
          | Function name  | RegexReplaceFile            |
          | Linked service | _Create the linked service_ |
          | Method         | Post                        |
          | Body           | ``{"name":"myfile.txt"}``   |
    1. Then click on ``publish all``
    1. Test the end-to-end setup by clicking on ``add trigger`` and then on ``trigger now``

