<%@ WebHandler Language="C#" Class="proxy" %>
/*
  This proxy page does not have any security checks. It is highly recommended
  that a user deploying this proxy page on their web server, add appropriate
  security checks, for example checking request path, username/password, target
  url, etc.
*/
using System;
using System.IO;
using System.Security.Principal;
using System.Web;
using System.Collections.Generic;
using System.Xml.Serialization;
using System.Web.Caching;
using System.Net;

/// <summary>
/// Forwards requests to an ArcGIS Server REST resource. Uses information in
/// the proxy.config file to determine properties of the server.
/// </summary>
public class proxy : IHttpHandler
{
    readonly ProxyConfig _config;

    public proxy()
    {
        _config = ProxyConfig.GetCurrentConfig();
    }
    
    public void ProcessRequest(HttpContext context)
    {   
        HttpResponse response = context.Response;

        // Get the URL requested by the client (take the entire querystring at once
        //  to handle the case of the URL itself containing querystring parameters)
        string uri = Uri.UnescapeDataString(context.Request.QueryString.ToString());

        // Debug: Ping to make sure avaiable (ie. http://localhost/TestApp/proxy.ashx?ping)
        if (uri.StartsWith("ping"))
        {
            context.Response.Write("Hello proxy");
            return;
        }

        // Get token, if applicable, and append to the request
        string token = getTokenFromConfigFile(uri);
        ICredentials credentials = null;

        if (string.IsNullOrEmpty(token))
            token = generateToken(uri);   

        if (!string.IsNullOrEmpty(token))
        {
            if (uri.Contains("?"))
                uri += "&token=" + token;
            else
                uri += "?token=" + token;
        }
        else if(!string.IsNullOrEmpty(_config.GetUser(uri))) // if using Windows/HTTP authentication
        {
            credentials = getCredentials(uri);
        }

        bool passCreds = getPassThroughFromConfigFile(uri);
        
        // Debug
        // WindowsIdentity creds = WindowsIdentity.GetCurrent();
        // context.Response.Write(creds.Name);
        // context.Response.Write("<br/>");
        // context.Response.Write(context.User.Identity.Name);
        // return;

        WindowsImpersonationContext wic = null;
        
        if (passCreds)
        {
            // Impersonate
            wic = ((WindowsIdentity) context.User.Identity).Impersonate();
            //WindowsImpersonationContext impersonationContext = creds.Impersonate();        
        }

        WebRequest req = WebRequest.Create(new Uri(HttpUtility.UrlDecode(uri)));
        req.Method = context.Request.HttpMethod;

        if (!passCreds)
        {
            // Assign credentials if using Windows/HTTP authentication with proxy.config credentials.
            if (credentials != null)
            {
                req.PreAuthenticate = true;
                req.Credentials = credentials;
            }
            else
            {
            		// Assign credentials using the default credentials, usually
            		// the account set as the app pool process owner.  We should not be impersonating here.
                req.PreAuthenticate = true;
                req.Credentials = CredentialCache.DefaultCredentials;           
            }
        }
        else
        {
            // Pass current credentials through.  We are impersonating.
            req.PreAuthenticate = true;
            req.Credentials = CredentialCache.DefaultCredentials;
        }

        // Set body of request for POST requests)
        if (context.Request.InputStream.Length > 0)
        {
            byte[] bytes = new byte[context.Request.InputStream.Length];
            context.Request.InputStream.Read(bytes, 0, (int)context.Request.InputStream.Length);
            req.ContentLength = bytes.Length;
            req.ContentType = "application/x-www-form-urlencoded";
            using (Stream outputStream = req.GetRequestStream())
            {
                outputStream.Write(bytes, 0, bytes.Length);
            }
        }

        // Send the request to the server
        System.Net.WebResponse serverResponse = null;
        try
        {
            serverResponse = req.GetResponse();
        }
        catch (System.Net.WebException webExc)
        {
            WindowsIdentity cred = WindowsIdentity.GetCurrent() ?? (WindowsIdentity) context.User.Identity;
            string name = cred.Name;
            
            // Comment out the StatusCode line to force the message to the browser.
            // Only do that for debugging as it will cause errors on the page for Map applications. 
            response.StatusCode = 500;
            response.StatusDescription = webExc.Status.ToString();
            response.Write("Error processing a request by " + name + " to URL " + uri);            
            response.Write("<br/><br/>");
            response.Write("AuthenticationType: " + cred.AuthenticationType);            
            response.Write("<br/><br/>");
            response.Write("ImpersonationLevel: " + cred.ImpersonationLevel);            
            response.Write("<br/><br/>");
            response.Write("IsAuthenticated: " + cred.IsAuthenticated);            
            response.Write("<br/><br/>");
            response.Write("IsAnonymous: " + cred.IsAnonymous);            
            response.Write("<br/><br/>");
            response.Write("IsGuest: " + cred.IsGuest);            
            response.Write("<br/><br/>");
            response.Write("IsSystem: " + cred.IsSystem);            
            response.Write("<br/><br/>");
            response.Write("Owner: " + cred.Owner);            
            response.Write("<br/><br/>");
            response.Write("Token: " + cred.Token);            
            response.Write("<br/><br/>");
            response.Write(webExc.Message);
            response.Write("<br/><br/>");
            //response.Write(webExc.Response);
            response.End();

            // End Impersonate
            if (passCreds) wic.Undo();
            return;
        }
        
        

        // Set up the response to the client
        if (serverResponse != null)
        {
            response.ContentType = serverResponse.ContentType;
            using (Stream byteStream = serverResponse.GetResponseStream())
            {
                BinaryReader br = new BinaryReader(byteStream);
                byte[] outb = br.ReadBytes((int)serverResponse.ContentLength);
                br.Close();

                // Send the image to the client
                // (Note: if large images/files sent, could modify this to send in chunks)
                response.OutputStream.Write(outb, 0, outb.Length);
                serverResponse.Close();
            }
        }
        response.End();

        // End Impersonate
        if (passCreds) wic.Undo(); 
    }

    public bool IsReusable
    {
        get
        {
            return false;
        }
    }

    // Gets the token for a server URL from a configuration file
    private string getTokenFromConfigFile(string uri)
    {
        try
        {            
            if (_config != null)
                return _config.GetToken(uri);
            else
                throw new ApplicationException(
                    "Proxy.config file does not exist at application root, or is not readable.");
        }
        catch (InvalidOperationException)
        {
            // Proxy is being used for an unsupported service (proxy.config has mustMatch="true")
            HttpResponse response = HttpContext.Current.Response;
            response.StatusCode = (int)System.Net.HttpStatusCode.Forbidden;
            response.End();
        }
        catch (Exception e)
        {
            if (e is ApplicationException)
                throw e;

            // just return an empty string at this point
            // -- may want to throw an exception, or add to a log file
        }

        return string.Empty;
    }

    // Gets the pass through flag for a server URL from a configuration file
    private bool getPassThroughFromConfigFile(string uri)
    {
        try
        {
            if (_config != null)
                return _config.IsPassThrough(uri);
            else
                throw new ApplicationException("Proxy.config file does not exist at application root, or is not readable.");
        }
        catch (InvalidOperationException)
        {
            // Proxy is being used for an unsupported service (proxy.config has mustMatch="true")
            HttpResponse response = HttpContext.Current.Response;
            response.StatusCode = (int)System.Net.HttpStatusCode.Forbidden;
            response.End();
        }
        catch (Exception e)
        {
            if (e is ApplicationException)
                throw e;

            // just return an empty string at this point
            // -- may want to throw an exception, or add to a log file
        }

        return false;
    }

    public System.Net.ICredentials getCredentials(string url)
    {
        try
        {
            if (_config != null)
            {
                foreach (ServerItem si in _config.ServerItems)
                    if (url.StartsWith(si.Url, true, null))
                    {
                        string url_401 = url.Substring(0, url.IndexOf("Server") + 6);

                        if (HttpRuntime.Cache[url_401] == null)
                        {
                            HttpWebRequest webRequest_401 = null;
                            webRequest_401 = (HttpWebRequest)HttpWebRequest.Create(url_401);
                            webRequest_401.ContentType = "text/xml;charset=\"utf-8\"";
                            webRequest_401.Method = "GET";
                            webRequest_401.Accept = "text/xml";

                            HttpWebResponse webResponse_401 = null;
                            while (webResponse_401 == null || webResponse_401.StatusCode != HttpStatusCode.OK)
                            {
                                try
                                {
                                    webResponse_401 = (System.Net.HttpWebResponse)webRequest_401.GetResponse();
                                }
                                catch (System.Net.WebException webex)
                                {
                                    System.Net.HttpWebResponse webexResponse = (HttpWebResponse)webex.Response;
                                    if (webexResponse.StatusCode == HttpStatusCode.Unauthorized)
                                    {
                                        if (webRequest_401.Credentials == null)
                                        {
                                            webRequest_401 = (HttpWebRequest)HttpWebRequest.Create(url_401);
                                            webRequest_401.Credentials =
                                                new System.Net.NetworkCredential(si.Username, si.Password, si.Domain);
                                        }
                                        else // if original credentials not accepted, throw exception                                        
                                            throw webex;
                                    }
                                    else // if status code unrecognized, throw exception                                          
                                        throw webex;
                                }
                                catch (Exception ex) { throw ex; }
                            }

                            if (webResponse_401 != null)
                                webResponse_401.Close();

                            HttpRuntime.Cache.Insert(url_401, webRequest_401.Credentials);
                        }
                        return (ICredentials)HttpRuntime.Cache[url_401];
                    }
            }
        }
        catch (InvalidOperationException)
        {
            // Proxy is being used for an unsupported service (proxy.config has mustMatch="true")
            HttpResponse response = HttpContext.Current.Response;
            response.StatusCode = (int)System.Net.HttpStatusCode.Forbidden;
            response.End();
        }
        catch (Exception e)
        {
            if (e is ApplicationException)
                throw e;

            // just return an empty string at this point
            // -- may want to throw an exception, or add to a log file
        }

        return null;
    }

    public string generateToken(string url)
    {
        try
        {
            if (_config != null)
            {
                foreach (ServerItem si in _config.ServerItems)
                    if (url.StartsWith(si.Url, true, null))
                    {
                        string theToken = null;

                        // If a token has been generated, check the expire time
                        if (HttpRuntime.Cache[si.Url] != null)
                        {
                            string existingToken = (HttpRuntime.Cache[si.Url] as
                            Dictionary<string, object>)["token"] as string;

                            DateTime expireTime = (DateTime)((HttpRuntime.Cache[si.Url] as
                            Dictionary<string, object>)["timeout"]);

                            // If token not expired, return it
                            if (DateTime.Now.CompareTo(expireTime) < 0)
                                theToken = existingToken;
                        }

                        // If token not available or expired, generate one and store it in cache
                        if (theToken == null)
                        {
                            string tokenServiceUrl = string.Format("{0}?request=getToken&username={1}&password={2}",
                                si.TokenUrl, si.Username, si.Password);

                            int timeout = 60;
                            if (si.Timeout > 0)
                                timeout = si.Timeout;

                            tokenServiceUrl += string.Format("&expiration={0}", timeout);
                            DateTime endTime = DateTime.Now.AddMinutes(timeout);

                            System.Net.WebRequest request = System.Net.WebRequest.Create(tokenServiceUrl);
                            System.Net.WebResponse response = request.GetResponse();
                            System.IO.Stream responseStream = response.GetResponseStream();
                            System.IO.StreamReader readStream = new System.IO.StreamReader(responseStream);
                            theToken = readStream.ReadToEnd();

                            Dictionary<string, object> serverItemEntries = new Dictionary<string, object>();
                            serverItemEntries.Add("token", theToken);
                            serverItemEntries.Add("timeout", endTime);

                            HttpRuntime.Cache.Insert(si.Url, serverItemEntries);
                        }
                        return theToken;
                    }
            }
        }
        catch (InvalidOperationException)
        {
            // Proxy is being used for an unsupported service (proxy.config has mustMatch="true")
            HttpResponse response = HttpContext.Current.Response;
            response.StatusCode = (int)System.Net.HttpStatusCode.Forbidden;
            response.End();
        }
        catch (Exception e)
        {
            if (e is ApplicationException)
                throw e;

            // just return an empty string at this point
            // -- may want to throw an exception, or add to a log file
        }

        return string.Empty;
    }
}

[XmlRoot("ProxyConfig")]
public class ProxyConfig
{
    #region Static Members

    private static object _lockobject = new object();

    public static ProxyConfig LoadProxyConfig(string fileName)
    {
        ProxyConfig config = null;

        lock (_lockobject)
        {
            if (System.IO.File.Exists(fileName))
            {
                XmlSerializer reader = new XmlSerializer(typeof(ProxyConfig));
                using (System.IO.StreamReader file = new System.IO.StreamReader(fileName))
                {
                    config = (ProxyConfig)reader.Deserialize(file);
                }
            }
        }

        return config;
    }

    public static ProxyConfig GetCurrentConfig()
    {
        ProxyConfig config = HttpRuntime.Cache["proxyConfig"] as ProxyConfig;
        if (config == null)
        {
            string fileName = GetFilename(HttpContext.Current);
            config = LoadProxyConfig(fileName);

            if (config != null)
            {
                CacheDependency dep = new CacheDependency(fileName);
                HttpRuntime.Cache.Insert("proxyConfig", config, dep);
            }
        }

        return config;
    }

    // Location of the proxy.config file
    public static string GetFilename(HttpContext context)
    {
        return context.Server.MapPath("proxy.config");
    }
    #endregion

    ServerItem[] serverItems;
    bool mustMatch;

    [XmlArray("serverItems")]
    [XmlArrayItem("serverItem")]
    public ServerItem[] ServerItems
    {
        get { return this.serverItems; }
        set { this.serverItems = value; }
    }

    [XmlAttribute("mustMatch")]
    public bool MustMatch
    {
        get { return mustMatch; }
        set { mustMatch = value; }
    }

    public string GetToken(string uri)
    {
        foreach (ServerItem su in serverItems)
        {
            if (su.MatchAll && uri.StartsWith(su.Url, StringComparison.InvariantCultureIgnoreCase))
            {
                return su.Token;
            }
            else
            {
                if (String.Compare(uri, su.Url, StringComparison.InvariantCultureIgnoreCase) == 0)
                    return su.Token;
            }
        }

        if (mustMatch)
            throw new InvalidOperationException();

        return string.Empty;
    }

    public bool IsPassThrough(string uri)
    {
        foreach (ServerItem su in serverItems)
        {
            if (su.MatchAll && uri.StartsWith(su.Url, StringComparison.InvariantCultureIgnoreCase)) return su.PassThrough;
            if (String.Compare(uri, su.Url, StringComparison.InvariantCultureIgnoreCase) == 0) return su.PassThrough;
        }
        
        return false;
    }
    
    public string GetUser(string uri)
    {
        foreach (ServerItem su in serverItems)
        {
            if (su.MatchAll && uri.StartsWith(su.Url, StringComparison.InvariantCultureIgnoreCase))
            {
                return su.Username;
            }
            else
            {
                if (String.Compare(uri, su.Url, StringComparison.InvariantCultureIgnoreCase) == 0)
                    return su.Username;
            }
        }

        if (mustMatch)
            throw new InvalidOperationException();

        return string.Empty;
    }
}

public class ServerItem
{
    string url;
    bool matchAll;
    bool passThrough;
    string token;
    string tokenUrl;
    string domain;
    string username;
    string password;
    int timeout;

    [XmlAttribute("url")]
    public string Url
    {
        get { return url; }
        set { url = value; }
    }

    [XmlAttribute("matchAll")]
    public bool MatchAll
    {
        get { return matchAll; }
        set { matchAll = value; }
    }

    [XmlAttribute("passThrough")]
    public bool PassThrough
    {
        get { return passThrough; }
        set { passThrough = value; }
    }

    [XmlAttribute("token")]
    public string Token
    {
        get { return token; }
        set { token = value; }
    }

    [XmlAttribute("tokenUrl")]
    public string TokenUrl
    {
        get { return tokenUrl; }
        set { tokenUrl = value; }
    }

    [XmlAttribute("domain")]
    public string Domain
    {
        get { return domain; }
        set { domain = value; }
    }

    [XmlAttribute("username")]
    public string Username
    {
        get { return username; }
        set { username = value; }
    }

    [XmlAttribute("password")]
    public string Password
    {
        get { return password; }
        set { password = value; }
    }

    [XmlAttribute("timeout")]
    public int Timeout
    {
        get { return timeout; }
        set { timeout = value; }
    }
}

